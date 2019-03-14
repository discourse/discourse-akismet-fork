module DiscourseAkismet
  class AdminModQueueController < Admin::AdminController
    requires_plugin 'discourse-akismet'

    before_action :deprecation_notice

    def index
      render_json_dump(
        posts: serialize_data(DiscourseAkismet.needs_review, PostSerializer, add_excerpt: true),
        enabled: SiteSetting.akismet_enabled?,
        stats: DiscourseAkismet.stats
      )
    end

    def confirm_spam
      if defined?(ReviewableAkismetPost)
        reviewable.perform(current_user, :confirm_spam)
      else
        DiscourseAkismet.move_to_state(post, 'confirmed_spam')
        log_confirmation(post, 'confirmed_spam')
      end

      render body: nil
    end

    def allow
      if defined?(ReviewableAkismetPost)
        reviewable.perform(current_user, :not_spam)
      else
        Jobs.enqueue(:update_akismet_status, post_id: post.id, status: 'ham')

        # It's possible the post was recovered already
        PostDestroyer.new(current_user, post).recover if post.deleted_at

        DiscourseAkismet.move_to_state(post, 'confirmed_ham')
        log_confirmation(post, 'confirmed_ham')
      end

      render body: nil
    end

    def dismiss
      if defined?(ReviewableAkismetPost)
        reviewable.perform(current_user, :ignore)
      else
        DiscourseAkismet.move_to_state(post, 'dismissed')
        log_confirmation(post, 'dismissed')
      end

      render body: nil
    end

    def delete_user
      if defined?(ReviewableAkismetPost)
        reviewable.perform(current_user, :confirm_delete)
      else
        user = post.user
        DiscourseAkismet.move_to_state(post, 'confirmed_spam')
        log_confirmation(post, 'confirmed_spam_deleted')

        if guardian.can_delete_user?(user)
          UserDestroyer.new(current_user).destroy(user, user_deletion_opts)
        end
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

    def deprecation_notice
      Discourse.deprecate('Akismet review queue is deprecated. Please use the reviewable API instead.')
    end

    def reviewable
      @reviewable ||= ReviewableAkismetPost.where(target_id: params[:post_id], target_type: Post.name)
    end

    def post
      @post ||= Post.with_deleted.find(params[:post_id])
    end
  end
end
