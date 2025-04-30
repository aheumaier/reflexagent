class CreateDomainAlerts < ActiveRecord::Migration[7.1]
  def change
    create_table :domain_alerts do |t|
      t.string :name, null: false
      t.string :severity, null: false
      t.jsonb :metric_data, null: false, default: {}
      t.float :threshold, null: false
      t.string :status, null: false, default: 'active'
      t.datetime :timestamp, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.timestamps
    end

    add_index :domain_alerts, :status
    add_index :domain_alerts, :severity
    add_index :domain_alerts, :name
  end
end
