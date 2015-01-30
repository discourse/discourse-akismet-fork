DiscourseAkismet::Engine.routes.draw do
  resource :admin_mod_queue, path: "/", constraints: StaffConstraint.new, only: [:index] do
    collection do
      get    "/"            => "admin_mod_queue#index"
      get    "index"        => "admin_mod_queue#index"
      post   "confirm_spam" => "admin_mod_queue#confirm_spam"
      post   "allow"        => "admin_mod_queue#allow"
      delete "delete_user"  => "admin_mod_queue#delete_user"
    end
  end
end
