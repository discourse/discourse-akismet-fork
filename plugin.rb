# frozen_string_literal: true

# name: discourse-akismet
# about: supports submitting posts to akismet for review
# version: 0.1.0
# authors: Michael Verdi, Robin Ward
# url: https://github.com/discourse/discourse-akismet

enabled_site_setting :akismet_enabled

load File.expand_path('../lib/discourse_akismet/engine.rb', __FILE__)
load File.expand_path('../lib/discourse_akismet/bouncer.rb', __FILE__)
load File.expand_path('../lib/discourse_akismet/users_bouncer.rb', __FILE__)
load File.expand_path('../lib/discourse_akismet/posts_bouncer.rb', __FILE__)
load File.expand_path('../lib/akismet.rb', __FILE__)
register_asset "stylesheets/reviewable-akismet-post-styles.scss"

after_initialize do
  %W[
    jobs/scheduled/check_for_spam_posts
    jobs/regular/check_users_for_spam
    jobs/regular/confirm_akismet_flagged_posts
    jobs/regular/check_akismet_post
    jobs/regular/update_akismet_status
    models/reviewable_akismet_post
    models/reviewable_akismet_user
    serializers/reviewable_akismet_post_serializer
    serializers/reviewable_akismet_user_serializer
  ].each do |filename|
    require_dependency File.expand_path("../#{filename}.rb", __FILE__)
  end
  register_reviewable_type ReviewableAkismetPost
  register_reviewable_type ReviewableAkismetUser

  add_model_callback(UserProfile, :before_save) do
    if bio_raw_changed? && bio_raw.present?
      DiscourseAkismet::UsersBouncer.new.enqueue_for_check(user)
    end
  end

  # Store extra data for akismet
  on(:post_created) do |post, params|
    bouncer = DiscourseAkismet::PostsBouncer.new
    if bouncer.should_check?(post)
      bouncer.store_additional_information(post, params)
      bouncer.move_to_state(post, 'new')

      # Enqueue checks for TL0 posts faster
      bouncer.enqueue_for_check(post) if post.user.trust_level == 0
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

      DB.exec sql, args
    end
  end

  staff_actions = %i[confirmed_spam confirmed_ham ignored confirmed_spam_deleted]
  extend_list_method(UserHistory, :staff_actions, staff_actions)
end
