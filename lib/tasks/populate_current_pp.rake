task populate_current_pp: :environment do
  PokemonPlayerSkill.all.each do |player_skill|
    # Assuming max_pp is an attribute in the Skill model
    max_pp = player_skill.skill.max_pp

    # Update current_pp in PokemonPlayerSkill with the calculated max_pp
    player_skill.update(current_pp: max_pp)
  end
end
