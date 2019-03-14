# name: discourse-akismet
# about: supports submitting posts to akismet for review
# version: 0.1.0
# authors: Michael Verdi, Robin Ward
# url: https://github.com/discourse/discourse-akismet

enabled_site_setting :akismet_enabled

# load the engine
load File.expand_path('../lib/discourse_akismet.rb', __FILE__)
load File.expand_path('../lib/akismet.rb', __FILE__)
load File.expand_path('../lib/discourse_akismet/engine.rb', __FILE__)

register_asset "stylesheets/mod-queue-styles.scss"
register_asset "stylesheets/reviewable-akismet-post-styles.scss"

after_initialize do
  require_dependency File.expand_path('../jobs/check_for_spam_posts.rb', __FILE__)
  require_dependency File.expand_path('../jobs/check_akismet_post.rb', __FILE__)
  require_dependency File.expand_path('../jobs/update_akismet_status.rb', __FILE__)

  begin
    'Reviewable'.constantize
    require_dependency File.expand_path('../models/reviewable_akismet_post.rb', __FILE__)
  rescue NameError
  end

  # Store extra data for akismet
  on(:post_created) do |post, params|
    if DiscourseAkismet.should_check_post?(post)
      DiscourseAkismet.move_to_state(post, 'new', params)

      # Enqueue checks for TL0 posts faster
      Jobs.enqueue(:check_akismet_post, post_id: post.id) if post.user.trust_level == 0
    end
  end

  # When staff agrees a flagged post is spam, send it to akismet
  on(:confirmed_spam_post) do |post|
    if SiteSetting.akismet_enabled?
      Jobs.enqueue(:update_akismet_status, post_id: post.id, status: 'spam')
    end
  end

  # If a user is anonymized, support anonymizing their IPs
  on(:user_anonymized) do |args|
    user = args[:user]
    opts = args[:opts]

    if user && opts && opts.has_key?(:anonymize_ip)
      sql = <<~SQL
        UPDATE post_custom_fields AS pcf
         SET value = :new_ip
         FROM posts AS p
         WHERE name = 'AKISMET_IP_ADDRESS'
           AND p.id = pcf.post_id
           AND p.user_id = :user_id
      SQL

      args = { user_id: user.id, new_ip: opts[:anonymize_ip] }

      # TODO remove post Discourse 2.1
      if defined? DB
        DB.exec sql, args
      else
        PostCustomField.exec_sql(sql, args)
      end
    end
  end

  add_to_class(:guardian, :can_review_akismet?) do
    user.try(:staff?)
  end

  add_to_serializer(:current_user, :akismet_review_count) do
    scope.can_review_akismet? ? DiscourseAkismet.needs_review.count : nil
  end
end

add_admin_route 'akismet.title', 'akismet'

# And mount the engine
Discourse::Application.routes.append do
  mount ::DiscourseAkismet::Engine, at: '/admin/plugins/akismet'
end
