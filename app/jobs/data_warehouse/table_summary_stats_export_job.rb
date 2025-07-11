# frozen_string_literal: true

require 'reporting/cloudwatch_client'

module DataWarehouse
  class TableSummaryStatsExportJob < BaseJob
    REPORT_NAME = 'table_summary_stats'

    TABLE_EXCLUSION_LIST = %w[
      agency_identities
      usps_confirmations
      usps_confirmation_codes
    ].freeze

    TIMESTAMP_OVERRIDE = {
      'sp_return_logs' => 'returned_at',
      'registration_logs' => 'registered_at',
      'letter_requests_to_usps_ftp_logs' => 'ftp_at',
      'deleted_users' => 'deleted_at',
    }.freeze

    def perform(timestamp)
      return if data_warehouse_disabled?

      idp_data = fetch_table_max_ids_and_counts(timestamp.end_of_day)
      cloudwatch_data = fetch_log_group_counts(timestamp)
      data = idp_data.merge(cloudwatch_data)
      upload_to_s3(data, timestamp)
    end

    def fetch_log_group_counts(timestamp)
      log_groups.each_with_object({}) do |log_group_name, result|
        table_name = 'logs.' + log_group_name.split('/').last.split('.').first
        result[table_name] = cloudwatch_client(log_group_name: log_group_name).fetch(
          query: cloudwatch_query(log_group_name),
          from: timestamp.beginning_of_day,
          to: timestamp.end_of_day,
        )[0]
        # set row count to 0 if nil or else convert to int
        offset = get_offset_count(log_group_name, timestamp)
        if result[table_name].nil?
          result[table_name] = { row_count: 0 }
        else
          result[table_name]['row_count'] = result[table_name]['row_count'].to_i - offset
        end
      end
    end

    def log_groups
      [
        "#{env}_/srv/idp/shared/log/events.log",
        "#{env}_/srv/idp/shared/log/production.log",
      ]
    end

    def env
      Identity::Hostdata.env
    end

    def cloudwatch_client(log_group_name: nil, slice_interval: 1.day)
      Reporting::CloudwatchClient.new(
        log_group_name: log_group_name,
        ensure_complete_logs: false,
        num_threads: 6,
        slice_interval: slice_interval,
      )
    end

    def log_stream_filter_map
      base_log_group = "#{env}_/srv/idp/shared/log"
      {
        "#{base_log_group}/events.log" => "@logStream like 'worker-i-' or @logStream like 'idp-i-'",
        "#{base_log_group}/production.log" => "@logStream like 'idp-i-'",
      }
    end

    def cloudwatch_query(log_group_name)
      <<~QUERY
        fields jsonParse(@message) as @messageJson
        | filter #{log_stream_filter_map[log_group_name]}
        | filter isPresent(@messageJson)
        | stats count() as row_count
      QUERY
    end

    def production_offset_query
      log_group_name = "#{env}_/srv/idp/shared/log/production.log"
      <<~QUERY
        fields jsonParse(@message) as @messageJson, concat(@timestamp, @message) as ts_plus_message
        | filter #{log_stream_filter_map[log_group_name]}
        | filter isPresent(@messageJson)
        | stats count() as cnt by ts_plus_message
        | stats sum(cnt - 1) as offset_count
      QUERY
    end

    def get_offset_count(log_group_name, timestamp)
      if log_group_name == "#{env}_/srv/idp/shared/log/production.log"
        # For production logs, exclude count of duplicates with same message & timestamp
        cw_client = cloudwatch_client(
          log_group_name: log_group_name,
          slice_interval: 30.minutes,
        )
        result = cw_client.fetch(
          query: production_offset_query,
          from: timestamp.beginning_of_day,
          to: timestamp.end_of_day,
        )
        result.sum { |h| h['offset_count'].to_i }
      else
        0
      end
    end

    def fetch_table_max_ids_and_counts(timestamp)
      Reports::BaseReport.transaction_with_timeout do
        max_ids_and_counts(timestamp)
      end
    end

    private

    def max_ids_and_counts(timestamp)
      active_tables = {}
      ActiveRecord::Base.connection.tables.each do |table|
        next if TABLE_EXCLUSION_LIST.include?(table)

        if table_has_id_column?(table)
          active_tables['idp.' + table] = fetch_max_id_and_count(table, timestamp)
        end
      end

      active_tables
    end

    def table_has_id_column?(table)
      ActiveRecord::Base.connection.columns(table).any? do |column|
        column.name == 'id' && column.type == :integer
      end
    end

    def fetch_max_id_and_count(table, timestamp)
      quoted_table = ActiveRecord::Base.connection.quote_table_name(table)
      query = <<-SQL
      SELECT COALESCE(MAX(id), 0) AS max_id, COUNT(*) AS row_count
      FROM #{quoted_table}
      SQL
      timestamp_column = 'created_at'
      timestamp_column = TIMESTAMP_OVERRIDE[table] if TIMESTAMP_OVERRIDE.key?(table)

      if table_has_column?(table, timestamp_column)
        quoted_timestamp = ActiveRecord::Base.connection.quote(timestamp)
        query += " WHERE #{timestamp_column} <= #{quoted_timestamp}"
      end

      result = ActiveRecord::Base.connection.execute(query).first
      result['timestamp_column'] = nil
      result['timestamp_column'] = 'created_at' if table_has_column?(table, 'created_at')
      result['timestamp_column'] = TIMESTAMP_OVERRIDE[table] if TIMESTAMP_OVERRIDE.key?(table)

      result
    end

    def table_has_column?(table, column_name)
      ActiveRecord::Base.connection.columns(table).map(&:name).include?(column_name)
    end

    def upload_to_s3(data, timestamp)
      _latest, path = generate_s3_paths(REPORT_NAME, 'json', now: timestamp)

      if bucket_name.present?
        upload_file_to_s3_bucket(
          path: path,
          body: data.to_json,
          content_type: 'application/json',
          bucket: bucket_name,
        )
      end
    end
  end
end
