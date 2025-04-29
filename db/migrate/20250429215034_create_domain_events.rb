class CreateDomainEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :domain_events, id: :bigserial do |t|
      t.uuid :aggregate_id, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      # Position as auto-incrementing column for global ordering
      t.bigint :position, null: false

      t.index :aggregate_id
      t.index :event_type
      t.index :position, unique: true
      t.index [:aggregate_id, :position]
    end

    # Create a sequence for the position column
    reversible do |dir|
      dir.up do
        execute <<-SQL
          CREATE SEQUENCE domain_events_position_seq;
          ALTER TABLE domain_events ALTER COLUMN position SET DEFAULT nextval('domain_events_position_seq');
        SQL
      end

      dir.down do
        execute <<-SQL
          DROP SEQUENCE IF EXISTS domain_events_position_seq;
        SQL
      end
    end
  end
end
