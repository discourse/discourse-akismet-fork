# frozen_string_literal: true

module Jobs
  class UpdateAkismetStatus < Jobs::Base

    def execute(args)
      raise Discourse::InvalidParameters.new(:target_id) unless args[:target_id].present?
      raise Discourse::InvalidParameters.new(:target_class) unless args[:target_class].present?
      raise Discourse::InvalidParameters.new(:status) unless args[:status].present?

      return unless SiteSetting.akismet_enabled?

      target = find_target(args[:target_class], args[:target_id])
      return unless target

      DiscourseAkismet.with_client do |client|
        if args[:target_class] == 'Post'
          submit_post_feedback(client, args[:status], target)
        elsif args[:target_class] == 'User'
          submit_user_feedback(client, args[:status], target)
        end
      end
    end

    private

    def find_target(klass_name, id)
      if klass_name == 'Post'
        klass_name.constantize.with_deleted.find_by(id: id)
      elsif klass_name == 'User'
        klass_name.constantize.find_by(id: id)
      end
    end

    def submit_post_feedback(client, status, post)
      args = DiscourseAkismet.args_for_post(post)

      if args[:status] == 'ham'
        client.submit_ham(args)
      elsif args[:status] == 'spam'
        client.submit_spam(args)
      end
    end

    def submit_user_feedback(client, status, user)
      DiscourseAkismet::UsersBouncer.new.submit_feedback(client, status, user)
    end
  end
end
