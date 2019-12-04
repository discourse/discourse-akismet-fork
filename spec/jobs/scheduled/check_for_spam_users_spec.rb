# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jobs::CheckForSpamUsers do

  before do
    SiteSetting.akismet_review_users = true
    SiteSetting.akismet_api_key = 'fake_key'
    SiteSetting.akismet_enabled = true
  end

  it 'works' do
    fake_client = mock("Akismet::Client").tap { |client| client.expects(:comment_check).returns(false) }
    Akismet::Client.expects(:new).returns(fake_client)

    user = Fabricate(:user, trust_level: TrustLevel[0]).tap do |u|
      u.user_profile.update(bio_raw: "I am batman")
      UserAuthTokenLog.create!(client_ip: '127.0.0.1', action: 'an_action', user: u)
    end
    DiscourseAkismet::UsersBouncer.new.move_to_state(user, 'new')

    subject.execute({})

    expect(user.reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]).to eq('confirmed_ham')
  end
end
