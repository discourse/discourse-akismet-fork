module DiscourseAkismet
  class AdminModQueueController < Admin::AdminController
    requires_plugin 'discourse-akismet'

    def index
      render_json_dump(
        posts: serialize_data(DiscourseAkismet.needs_review, PostSerializer, add_excerpt: true),
        enabled: SiteSetting.akismet_enabled?,
        stats: DiscourseAkismet.stats
      )
    end

    def confirm_spam
      post = Post.with_deleted.find(params[:post_id])
      DiscourseAkismet.move_to_state(post, 'confirmed_spam')
      log_confirmation(post, 'confirmed_spam')
      render body: nil
    end

    def allow
      post = Post.with_deleted.find(params[:post_id])

      Jobs.enqueue(:update_akismet_status, post_id: post.id, status: 'ham')

      # It's possible the post was recovered already
      if post.deleted_at
        PostDestroyer.new(current_user, post).recover
      end

      DiscourseAkismet.move_to_state(post, 'confirmed_ham')
      log_confirmation(post, 'confirmed_ham')

      render body: nil
    end

    def dismiss
      post = Post.with_deleted.find(params[:post_id])
      DiscourseAkismet.move_to_state(post, 'dismissed')
      log_confirmation(post, 'dismissed')

      render body: nil
    end

    def delete_user
      post = Post.with_deleted.find(params[:post_id])
      user = post.user
      DiscourseAkismet.move_to_state(post, 'confirmed_spam')
      log_confirmation(post, 'confirmed_spam_deleted')

      if guardian.can_delete_user?(user)
        UserDestroyer.new(current_user).destroy(user, user_deletion_opts)
      end

      render body: nil
    end

    private

    def log_confirmation(post, custom_type)
      topic = post.topic || Topic.with_deleted.find(post.topic_id)

      StaffActionLogger.new(current_user).log_custom(custom_type,
        post_id: post.id,
        topic_id: topic.id,
        created_at: post.created_at,
      )
    end

    def user_deletion_opts
      base = {
        context: I18n.t('akismet.delete_reason', performed_by: current_user.username),
        delete_posts: true
      }

      if Rails.env.production? && ENV["Staging"].nil?
        base.merge!(block_email: true, block_ip: true)
      end

      base
    end
  end
end
