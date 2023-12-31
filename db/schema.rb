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

ActiveRecord::Schema[7.1].define(version: 2023_12_18_061016) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "battle_histories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "pokedexes", force: :cascade do |t|
    t.string "name"
    t.integer "base_hp"
    t.integer "base_attack"
    t.integer "base_defense"
    t.integer "base_speed"
    t.string "image_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "type_id"
    t.index ["type_id"], name: "index_pokedexes_on_type_id"
  end

  create_table "pokemon_battle_details", force: :cascade do |t|
    t.bigint "pokemon_battle_id", null: false
    t.bigint "pokemon_player_id", null: false
    t.string "result"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pokemon_battle_id"], name: "index_pokemon_battle_details_on_pokemon_battle_id"
    t.index ["pokemon_player_id"], name: "index_pokemon_battle_details_on_pokemon_player_id"
  end

  create_table "pokemon_battles", force: :cascade do |t|
    t.datetime "time", precision: nil
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "current_turn"
    t.integer "pokemon1_id"
    t.integer "pokemon2_id"
    t.integer "pokemon_winner_id"
    t.integer "pokemon_loser_id"
    t.integer "pokemon1_max_hp"
    t.integer "pokemon2_max_hp"
  end

  create_table "pokemon_player_skills", force: :cascade do |t|
    t.bigint "pokemon_player_id", null: false
    t.bigint "skill_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "current_pp"
    t.index ["pokemon_player_id"], name: "index_pokemon_player_skills_on_pokemon_player_id"
    t.index ["skill_id"], name: "index_pokemon_player_skills_on_skill_id"
  end

  create_table "pokemon_players", force: :cascade do |t|
    t.string "name"
    t.bigint "pokedex_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "max_hp"
    t.integer "current_hp"
    t.integer "attack"
    t.integer "defense"
    t.integer "speed"
    t.index ["pokedex_id"], name: "index_pokemon_players_on_pokedex_id"
  end

  create_table "skills", force: :cascade do |t|
    t.string "name"
    t.integer "power"
    t.integer "max_pp"
    t.bigint "type_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["type_id"], name: "index_skills_on_type_id"
  end

  create_table "types", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "pokedexes", "types"
  add_foreign_key "pokemon_battle_details", "pokemon_battles"
  add_foreign_key "pokemon_battle_details", "pokemon_players"
  add_foreign_key "pokemon_player_skills", "pokemon_players"
  add_foreign_key "pokemon_player_skills", "skills"
  add_foreign_key "pokemon_players", "pokedexes"
  add_foreign_key "skills", "types"
end
