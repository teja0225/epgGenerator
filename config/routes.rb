Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  root "epg#index"
  get 'epg/index'
  post 'epg/epg_generator'
end
