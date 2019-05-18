# frozen_string_literal: true

require_dependency 'reviewable_serializer'

class ReviewableAkismetUserSerializer < ReviewableSerializer
  payload_attributes :username, :name, :email, :bio
end
