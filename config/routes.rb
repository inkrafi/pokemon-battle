Rails.application.routes.draw do
  root 'static_pages#home'
  get '/about', to: 'static_pages#about'

  resources :cards, only: [:index, :show]

  resources :games, only: [:index, :new, :create, :show] do
    collection { post :online }
    member do
      post :actions
      post :reveal
    end
  end

  # The link an online host sends to a friend
  get  'join/:token', to: 'games#invite', as: :join_game
  post 'join/:token', to: 'games#join'

  resources :decks do
    member do
      post   :copy
      post   'cards/:card_id', to: 'deck_cards#create',  as: :add_card
      delete 'cards/:card_id', to: 'deck_cards#destroy', as: :remove_card
    end
  end
end
