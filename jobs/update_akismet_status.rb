# frozen_string_literal: true

module Jobs
  class UpdateAkismetStatus < Jobs::Base

    def execute(args)
      raise Discourse::InvalidParameters.new(:target_id) unless args[:target_id].present?
      raise Discourse::InvalidParameters.new(:target_class) unless args[:target_class].present?
      raise Discourse::InvalidParameters.new(:status) unless args[:status].present?

      return unless SiteSetting.akismet_enabled?

      target = if args[:target_class] == 'Post'
        args[:target_class].constantize.with_deleted.where(id: args[:target_id]).first
      elsif args[:target_class] == 'User'
        args[:target_class].constantize.where(id: args[:target_id]).first
      end

      return unless target

      akismet_args = if args[:target_class] == 'Post'
        DiscourseAkismet.args_for_post(target)
      elsif args[:target_class] == 'User'
        DiscourseAkismet.args_for_user(target)
      end

      DiscourseAkismet.with_client do |client|
        if args[:status] == 'ham'
          client.submit_ham(akismet_args)
        elsif args[:status] == 'spam'
          client.submit_spam(akismet_args)
        end
      end
    end
  end
end
