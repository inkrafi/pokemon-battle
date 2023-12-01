# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2023_12_01_124052) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "pokedexes", force: :cascade do |t|
    t.string "name"
    t.integer "hp"
    t.integer "attack"
    t.integer "defense"
    t.integer "speed"
    t.string "image_url"
    t.bigint "type_id", null: false
    t.bigint "skill_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["skill_id"], name: "index_pokedexes_on_skill_id"
    t.index ["type_id"], name: "index_pokedexes_on_type_id"
  end

  create_table "pokemons", force: :cascade do |t|
    t.string "name"
    t.bigint "pokedex_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["pokedex_id"], name: "index_pokemons_on_pokedex_id"
  end

  create_table "skills", force: :cascade do |t|
    t.string "name"
    t.integer "power"
    t.integer "max_pp"
    t.bigint "type_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["type_id"], name: "index_skills_on_type_id"
  end

  create_table "types", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  add_foreign_key "pokedexes", "skills"
  add_foreign_key "pokedexes", "types"
  add_foreign_key "pokemons", "pokedexes"
  add_foreign_key "skills", "types"
end
