Rails.application.routes.draw do
  root 'static_pages#home'
  get  '/about', to: 'static_pages#about'
  post '/pokemon_battles/attack', to: 'pokemon_battles#attack'
  resources :pokedexes
  resources :pokemons
  resources :pokemon_battles
  resource  :pokemon_battle_details
end
