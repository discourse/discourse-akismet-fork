# frozen_string_literal: true

module Jobs
  class UpdateAkismetStatus < Jobs::Base
    def execute(args)
      return unless SiteSetting.akismet_enabled?

      akismet_feedback = args[:feedback]
      status = args[:status]
      raise Discourse::InvalidParameters.new(:feedback) unless akismet_feedback
      raise Discourse::InvalidParameters.new(:status) unless status

      DiscourseAkismet.with_client do |client|
        if status == 'ham'
          client.submit_ham(akismet_feedback)
        elsif status == 'spam'
          client.submit_spam(akismet_feedback)
        end
      end
    end
  end
end
