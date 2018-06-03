Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  get '/blog_metrics/bookmarks' => 'blog_metrics#count_bookmarks'
  get '/blog_metrics/subscribers' => 'blog_metrics#count_subscribers'
  get '/blog_metrics/active_visitors' => 'blog_metrics#count_active_visitors'
  post '/blog_metrics/test' => 'blog_metrics#test'
end
