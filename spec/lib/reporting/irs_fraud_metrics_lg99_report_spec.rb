require 'rails_helper'
require 'reporting/irs_fraud_metrics_lg99_report'

RSpec.describe Reporting::IrsFraudMetricsLg99Report do
  let(:issuer) { 'my:example:issuer' }
  let(:time_range) { Date.new(2022, 1, 1).in_time_zone('UTC').all_month }
  let(:expected_definitions_table) do
    [
      ['Metric', 'Unit', 'Definition'],
      ['Fraud Rules Catch Count', 'Count',
       'The count of unique accounts flagged for fraud review.'],
      ['Credentials Disabled', 'Count',
       'The count of unique accounts suspended due to ' + '
         suspected fraudulent activity within the reporting month.'],
      ['Credentials Reinstated', 'Count',
       'The count of unique suspended accounts ' + '
         that are reinstated within the reporting month.'],
    ]
  end
  let(:expected_overview_table) do
    [
      ['Report Timeframe', "#{time_range.begin} to #{time_range.end}"],
      ['Report Generated', Time.zone.today.to_s],
      ['Issuer', issuer],
    ]
  end
  let(:expected_lg99_metrics_table) do
    [
      ['Metric', 'Total', 'Range Start', 'Range End'],
      ['Fraud Rules Catch Count', '5', time_range.begin.to_s,
       time_range.end.to_s],
      ['Credentials Disabled', '2', time_range.begin.to_s, time_range.end.to_s],
      ['Credentials Reinstated', '1', time_range.begin.to_s, time_range.end.to_s],
    ]
  end

  subject(:report) { Reporting::IrsFraudMetricsLg99Report.new(issuers: [issuer], time_range:) }

  before do
    travel_to Time.zone.now.beginning_of_day
    stub_cloudwatch_logs(
      [
        { 'user_id' => 'user1', 'name' => 'IdV: Final Resolution' },
        { 'user_id' => 'user1', 'name' => 'IdV: Final Resolution' },

        { 'user_id' => 'user2', 'name' => 'IdV: Final Resolution' },

        { 'user_id' => 'user3', 'name' => 'IdV: Final Resolution' },

        { 'user_id' => 'user4', 'name' => 'IdV: Final Resolution' },

        { 'user_id' => 'user5', 'name' => 'IdV: Final Resolution' },

        { 'user_id' => 'user6', 'name' => 'User Suspension: Suspended' },
        { 'user_id' => 'user6', 'name' => 'User Suspension: Reinstated' },

        { 'user_id' => 'user7', 'name' => 'User Suspension: Suspended' },
      ],
    )
    user7.profiles.verified.last.update(created_at: 1.day.ago, activated_at: 1.day.ago) if user7
  end

  let!(:user6) do
    create(
      :user,
      :proofed,
      :reinstated,
      uuid: 'user6',
      suspended_at: 3.days.from_now,
      reinstated_at: 6.days.from_now,
    )
  end
  let!(:user7) { create(:user, :proofed, :suspended, uuid: 'user7') }

  describe '#definitions_table' do
    it 'renders a definitions table' do
      aggregate_failures do
        report.definitions_table.zip(expected_definitions_table).each do |actual, expected|
          expect(actual).to eq(expected)
        end
      end
    end
  end

  describe '#overview_table' do
    it 'renders an overview table' do
      aggregate_failures do
        report.overview_table.zip(expected_overview_table).each do |actual, expected|
          expect(actual).to eq(expected)
        end
      end
    end
  end

  describe '#lg99_metrics_table' do
    it 'renders a lg99 metrics table' do
      aggregate_failures do
        report.lg99_metrics_table.zip(expected_lg99_metrics_table).each do |actual, expected|
          expect(actual).to eq(expected)
        end
      end
    end
  end

  describe '#user_days_to_suspension_avg' do
    context 'when there are suspended users' do
      it 'returns average time to suspension' do
        expect(report.user_days_to_suspension_avg).to eq(1.5)
      end
    end

    context 'when there are no users' do
      let(:user6) { nil }
      let(:user7) { nil }

      it 'returns n/a' do
        expect(report.user_days_to_suspension_avg).to eq('n/a')
      end
    end
  end

  describe '#user_days_to_reinstatement_avg' do
    context 'where there are reinstated users' do
      it 'returns average time to reinstatement' do
        expect(report.user_days_to_reinstatement_avg).to eq(3.0)
      end
    end

    context 'when there are no users' do
      let(:user6) { nil }
      let(:user7) { nil }

      it 'returns n/a' do
        expect(report.user_days_to_reinstatement_avg).to eq('n/a')
      end
    end
  end

  describe '#user_days_proofed_to_suspended_avg' do
    context 'when there are suspended users' do
      it 'returns average time proofed to suspension' do
        expect(report.user_days_proofed_to_suspension_avg).to eq(2.0)
      end
    end

    context 'when there are no users' do
      let(:user6) { nil }
      let(:user7) { nil }

      it 'returns n/a' do
        expect(report.user_days_proofed_to_suspension_avg).to eq('n/a')
      end
    end
  end

  describe '#as_emailable_reports' do
    let(:expected_reports) do
      [
        Reporting::EmailableReport.new(
          title: 'Definitions',
          filename: 'definitions',
          table: expected_definitions_table,
        ),
        Reporting::EmailableReport.new(
          title: 'Overview',
          filename: 'overview',
          table: expected_overview_table,
        ),
        Reporting::EmailableReport.new(
          title: 'Monthly Fraud Metrics Jan-2022',
          filename: 'lg99_metrics',
          table: expected_lg99_metrics_table,
        ),
      ]
    end
    it 'return expected table for email' do
      expect(report.as_emailable_reports).to eq expected_reports
    end
  end

  describe '#cloudwatch_client' do
    let(:opts) { {} }
    let(:subject) { described_class.new(issuers: [issuer], time_range:, **opts) }
    let(:default_args) do
      {
        num_threads: 1,
        ensure_complete_logs: true,
        slice_interval: 6.hours,
        progress: false,
        logger: nil,
      }
    end

    describe 'when all args are default' do
      it 'creates a client with the default options' do
        expect(Reporting::CloudwatchClient).to receive(:new).with(default_args)

        subject.cloudwatch_client
      end
    end

    describe 'when verbose is passed in' do
      let(:opts) { { verbose: true } }
      let(:logger) { double Logger }

      before do
        expect(Logger).to receive(:new).with(STDERR).and_return logger
        default_args[:logger] = logger
      end

      it 'creates a client with the expected logger' do
        expect(Reporting::CloudwatchClient).to receive(:new).with(default_args)

        subject.cloudwatch_client
      end
    end

    describe 'when progress is passed in as true' do
      let(:opts) { { progress: true } }
      before { default_args[:progress] = true }

      it 'creates a client with progress as true' do
        expect(Reporting::CloudwatchClient).to receive(:new).with(default_args)

        subject.cloudwatch_client
      end
    end

    describe 'when threads is passed in' do
      let(:opts) { { threads: 17 } }
      before { default_args[:num_threads] = 17 }

      it 'creates a client with the expected thread count' do
        expect(Reporting::CloudwatchClient).to receive(:new).with(default_args)

        subject.cloudwatch_client
      end
    end

    describe 'when slice is passed in' do
      let(:opts) { { slice: 2.weeks } }
      before { default_args[:slice_interval] = 2.weeks }

      it 'creates a client with expected time slice' do
        expect(Reporting::CloudwatchClient).to receive(:new).with(default_args)

        subject.cloudwatch_client
      end
    end
  end
end
