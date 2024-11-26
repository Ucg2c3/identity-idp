require 'rails_helper'

RSpec.describe DataWarehouse::TableSummaryStatsExportJob, type: :job do
  let(:timestamp) { Date.new(2024, 10, 10).in_time_zone('UTC').end_of_day }
  let(:job) { described_class.new }
  let(:expected_bucket) { 'login-gov-analytics-export-test-1234-us-west-2' }
  let(:test_on_tables) { ['users'] }
  let(:s3_data_warehouse_bucket_prefix) { 'login-gov-analytics-export' }
  let(:data_warehouse_enabled) { true }

  let(:expected_json) do
    {
      'users' => {
        'max_id' => 2,
        'row_count' => 2,
      },
    }.to_json
  end

  let(:s3_metadata) do
    {
      body: anything,
      content_type: 'application/json',
      bucket: 'login-gov-analytics-export-int-1234-us-west-1',
    }
  end

  before do
    allow(Identity::Hostdata).to receive(:env).and_return('int')
    allow(Identity::Hostdata).to receive(:aws_account_id).and_return('1234')
    allow(Identity::Hostdata).to receive(:aws_region).and_return('us-west-1')
    allow(IdentityConfig.store).to receive(:s3_data_warehouse_bucket_prefix).
      and_return(s3_data_warehouse_bucket_prefix)
    allow(IdentityConfig.store).to receive(:data_warehouse_enabled).
      and_return(data_warehouse_enabled)
    Aws.config[:s3] = {
      stub_responses: {
        put_object: {},
      },
    }
  end

  describe '#perform' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:tables).and_return(test_on_tables)
      add_data_to_tables
    end

    context 'when data_warehouse_enabled is false' do
      let(:data_warehouse_enabled) { false }

      it 'does not perform the job' do
        allow(IdentityConfig.store).to receive(:data_warehouse_enabled).
          and_return(data_warehouse_enabled)
        expect(job).not_to receive(:fetch_table_max_ids_and_counts)
        expect(job).not_to receive(:upload_file_to_s3_bucket)
      end
    end

    context 'when database tables contain data' do
      it 'generates correct JSON from database tables' do
        json_data = job.fetch_table_max_ids_and_counts(timestamp)

        expect(json_data.to_json).to eq(expected_json)
      end
    end

    context 'when tables are empty' do
      let(:expected_empty_json) { { 'users' => { 'max_id' => 0, 'row_count' => 0 } }.to_json }

      before do
        User.delete_all # Clear the User table to simulate emptiness
      end

      it 'returns nil max_id and 0 row_count for empty tables' do
        json_data = job.fetch_table_max_ids_and_counts(timestamp)

        expect { job.perform(timestamp) }.not_to raise_error
        expect(json_data.to_json).to eq(expected_empty_json)
      end
    end

    context 'when tables are missing the id column' do
      let(:expected_empty_json) { {}.to_json }

      before do
        allow(ActiveRecord::Base.connection).to receive(:tables).and_return(['non_id_table'])
        allow(ActiveRecord::Base.connection).to receive(:columns).with('non_id_table').
          and_return([double(name: 'name')])
      end

      it 'skips tables without an id column' do
        json_data = job.fetch_table_max_ids_and_counts(timestamp)

        expect { job.perform(timestamp) }.not_to raise_error
        expect(json_data.to_json).to eq(expected_empty_json)
      end
    end

    context 'when uploading to S3' do
      it 'uploads a file to S3 based on the report date' do
        expect(job).to receive(:upload_file_to_s3_bucket).with(
          path: 'table_summary_stats/2024/2024-10-10_table_summary_stats.json',
          **s3_metadata,
        ).exactly(1).time.and_call_original

        job.perform(timestamp)
      end
    end
  end

  def add_data_to_tables
    User.create!(id: 1, created_at: (timestamp - 1.hour))
    User.create!(id: 2, created_at: (timestamp - 1.day))
  end
end
