Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  get '/blog_metrics/bookmarks' => 'blog_metrics#count_bookmarks'
end
