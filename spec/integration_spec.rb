require 'byebug'
require 'spec_helper'

describe PerconaMigrator do
  class Comment < ActiveRecord::Base; end

  def indexes_from(table_name)
    ActiveRecord::Base.connection.indexes(:comments)
  end

  def unique_indexes_from(table_name)
    indexes = indexes_from(:comments)
    indexes.select(&:unique).map(&:name)
  end

  let(:direction) { :up }
  # TODO: use this logger
  let(:logger) { double(:logger, puts: true) }

  before { ActiveRecord::Migration.verbose = false }

  it 'has a version number' do
    expect(PerconaMigrator::VERSION).not_to be nil
  end

  context 'creating/removing columns' do
    let(:version) { 1 }

    describe 'command', integration: true do
      before { allow(PerconaMigrator::Runner).to receive(:execute) }

      it 'runs pt-online-schema-change' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version
        ).migrate

        expect(PerconaMigrator::Runner).to(
          have_received(:execute)
          .with(include('pt-online-schema-change'), kind_of(NullLogger))
        )
      end

      it 'executes the migration' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version
        ).migrate

        expect(PerconaMigrator::Runner).to(
          have_received(:execute)
          .with(include('--execute'), kind_of(NullLogger))
        )
      end

      it 'does not define --recursion-method' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version
        ).migrate

        expect(PerconaMigrator::Runner).to(
          have_received(:execute)
          .with(include('--recursion-method=none'), kind_of(NullLogger))
        )
      end

      it 'sets the --alter-foreign-keys-method option to auto' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version
        ).migrate

        expect(PerconaMigrator::Runner).to(
          have_received(:execute)
          .with(include('--alter-foreign-keys-method=auto'), kind_of(NullLogger))
        )
      end
    end

    context 'creating column' do
      let(:direction) { :up }

      it 'adds the column in the DB table' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version
        ).migrate

        Comment.reset_column_information
        expect(Comment.column_names).to include('some_id_field')
      end

      it 'marks the migration as up' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version
        ).migrate

        expect(ActiveRecord::Migrator.current_version).to eq(version)
      end
    end

    context 'droping column' do
      let(:direction) { :down }

      before do
        ActiveRecord::Migrator.new(
          :up,
          [MIGRATION_FIXTURES],
          version
        ).migrate
      end

      it 'drops the column from the DB table' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version - 1
        ).migrate

        Comment.reset_column_information
        expect(Comment.column_names).not_to include('some_id_field')
      end

      it 'marks the migration as down' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version - 1
        ).migrate

        expect(ActiveRecord::Migrator.current_version).to eq(version - 1)
      end
    end
  end

  context 'specifing connection vars and parsing tablename', integration: true do
    let(:host)      { 'test_host' }
    let(:user)      { 'test_user' }
    let(:password)  { 'test_password' }
    let(:db_name)   { 'test_db' }

    let(:version) { 1 }

    before { allow(PerconaMigrator::Runner).to receive(:execute) }

    before do
      allow(ENV).to receive(:[]).with('PERCONA_DB_HOST').and_return(host)
      allow(ENV).to receive(:[]).with('PERCONA_DB_USER').and_return(user)
      allow(ENV).to receive(:[]).with('PERCONA_DB_PASSWORD').and_return(password)
      allow(ENV).to receive(:[]).with('PERCONA_DB_NAME').and_return(db_name)
    end

    it 'executes the percona command with the right connection details' do
      ActiveRecord::Migrator.new(
        direction,
        [MIGRATION_FIXTURES],
        version
      ).migrate

      expect(PerconaMigrator::Runner).to(
        have_received(:execute)
        .with(include("-h #{host} -u #{user} -p #{password} D=#{db_name},t=comments"), kind_of(NullLogger))
      )
    end

    context 'when there is no password' do
      before do
        allow(ENV).to receive(:[]).with('PERCONA_DB_PASSWORD').and_return(nil)
      end

      it 'executes the percona command with the right connection details' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version
        ).migrate

        expect(PerconaMigrator::Runner).to(
          have_received(:execute)
          .with(include("-h #{host} -u #{user} D=#{db_name},t=comments"), kind_of(NullLogger))
        )
      end
    end
  end

  context 'adding/removing indexes', index: true do
    let(:version) { 2 }

    context 'adding indexes' do
      let(:direction) { :up }

      # TODO: Create it directly like this?
      before do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          1
        ).migrate
      end

      it 'executes the percona command' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version
        ).migrate

        expect(indexes_from(:comments).map(&:name)).to(
          contain_exactly('index_comments_on_some_id_field')
        )
      end

      it 'marks the migration as up' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version
        ).migrate

        expect(ActiveRecord::Migrator.current_version).to eq(version)
      end
    end

    context 'removing indexes' do
      let(:direction) { :down }

      before do
        ActiveRecord::Migrator.new(
          :up,
          [MIGRATION_FIXTURES],
          1
        ).migrate

        ActiveRecord::Migrator.new(
          :up,
          [MIGRATION_FIXTURES],
          version
        ).migrate
      end

      it 'executes the percona command' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version - 1
        ).migrate

        expect(indexes_from(:comments).map(&:name)).not_to(
          include('index_comments_on_some_id_field')
        )
      end

      it 'marks the migration as down' do
        ActiveRecord::Migrator.new(
          direction,
          [MIGRATION_FIXTURES],
          version - 1
        ).migrate

        expect(ActiveRecord::Migrator.current_version).to eq(1)
      end
    end
  end

  context 'adding/removing unique indexes', index: true do
    let(:version) { 3 }

    context 'adding indexes' do
      let(:direction) { :up }

      before do
        ActiveRecord::Migrator.new(:up, [MIGRATION_FIXTURES], 1).migrate
      end

      it 'executes the percona command' do
        ActiveRecord::Migrator.run(direction, [MIGRATION_FIXTURES], version)

        expect(unique_indexes_from(:comments)).to(
          match_array(['index_comments_on_some_id_field'])
        )
      end

      it 'marks the migration as up' do
        ActiveRecord::Migrator.run(direction, [MIGRATION_FIXTURES], version)
        expect(ActiveRecord::Migrator.current_version).to eq(version)
      end
    end

    context 'removing indexes' do
      let(:direction) { :down }

      before do
        ActiveRecord::Migrator.new(:up, [MIGRATION_FIXTURES], 1).migrate
        ActiveRecord::Migrator.run(:up, [MIGRATION_FIXTURES], version)
      end

      it 'executes the percona command' do
        ActiveRecord::Migrator.run(direction, [MIGRATION_FIXTURES], version)

        expect(unique_indexes_from(:comments)).not_to(
          match_array(['index_comments_on_some_id_field'])
        )
      end

      it 'marks the migration as down' do
        ActiveRecord::Migrator.run(direction, [MIGRATION_FIXTURES], version)
        expect(ActiveRecord::Migrator.current_version).to eq(1)
      end
    end
  end

  context 'working with an empty migration' do
    let(:version) { 5 }

    subject(:migration) do
      ActiveRecord::Migrator.new(
        direction,
        [MIGRATION_FIXTURES],
        version
      ).migrate
    end

    it 'errors' do
      expect { migration }.to raise_error(/An error has occurred, all later migrations canceled/i)
    end
  end

  context 'working with broken migration' do
    let(:version) { 6 }

    subject(:migration) do
      ActiveRecord::Migrator.new(
        direction,
        [MIGRATION_FIXTURES],
        version
      ).migrate
    end

    it 'errors' do
      expect { migration }.to raise_error(/An error has occurred, all later migrations canceled/i)
    end
  end

  context 'working with non-lhm migration' do
    let(:version) { 7 }

    subject(:migration) do
      ActiveRecord::Migrator.new(
        direction,
        [MIGRATION_FIXTURES],
        version
      ).migrate
    end

    it 'errors' do
      expect { migration }.to raise_error(/An error has occurred, all later migrations canceled/i)
    end
  end

  # TODO: Handle LHM migrations, using an adapter, but not as part the public API
  context 'detecting lhm migrations' do
    subject { described_class.lhm_migration?(version) }

    context 'lhm migration' do
      let(:version) { 1 }
      xit { is_expected.to be_truthy }
    end

    context 'working with an non lhm migration' do
      let(:version) { 7 }
      xit { is_expected.to be_falsey }
    end
  end
end
