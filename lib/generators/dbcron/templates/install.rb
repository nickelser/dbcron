class <%= migration_class_name %> < ActiveRecord::Migration
  def self.up
    create_table :dbcron_hosts, force: true do |t|
      t.column :uuid, :string
      t.column :hostname, :string
      t.column :pid, :integer
      t.column :started, :datetime
      t.column :last_seen, :datetime
    end

    create_table :dbcron_entries, force: true do |t|
      t.column :task, :string
      t.column :last, :datetime
    end

    add_index :dbcron_hosts, :uuid, unique: true, name: "dbcron_hosts_uuid_index"
    add_index :dbcron_entries, :task, unique: true, name: "dbcron_entry_task_index"
  end

  def self.down
    drop_table :dbcron_hosts
    drop_table :dbcron_entries
  end
end
