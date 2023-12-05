Rails.application.routes.draw do
  root   'static_pages#home'
  get    '/about',       to: 'static_pages#about'
  resources :pokemons
  resources :pokemons2
end
