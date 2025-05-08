# frozen_string_literal: true

class CreateTeamsAndRepositories < ActiveRecord::Migration[7.1]
  def change
    # Create teams table
    create_table :teams do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.timestamps

      t.index :slug, unique: true
    end

    # Create code_repositories table with foreign key to teams
    create_table :code_repositories do |t|
      t.string :name, null: false
      t.string :url
      t.string :provider, default: "github", null: false
      t.references :team, foreign_key: true
      t.timestamps

      t.index :name
      t.index [:name, :provider], unique: true
    end
  end
end
