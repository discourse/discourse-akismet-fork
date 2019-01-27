require 'rails_helper'

describe Jobs::CheckAkismetUser do

  let(:user) { Fabricate(:newuser) }

  let(:mock_response) { Struct.new(:status, :body, :headers) }

  before do
  	SiteSetting.akismet_api_key = 'not_a_real_key'
    SiteSetting.akismet_enabled = true

    user_profile = user.user_profile
    user_profile.bio_raw = 'random bio'
    user_profile.save
  end

  it 'moves to needs_review for tl0 spam user' do
  	Excon.expects(:post).returns(mock_response.new(200, 'true'))

   	described_class.new.execute({user_id: user.id})

    expect(user.custom_fields[DiscourseAkismet::AKISMET_STATE_KEY]).to eq(DiscourseAkismet::NEEDS_REVIEW)
  end

  it 'moves to checked for tl0 user who is not selected as spam' do
    Excon.expects(:post).returns(mock_response.new(200, 'false'))

    described_class.new.execute({user_id: user.id})

    expect(user.custom_fields[DiscourseAkismet::AKISMET_STATE_KEY]).to eq(DiscourseAkismet::CHECKED)
  end

  it 'does not check spam for user above tl0' do
    user.trust_level = 1
    user.save

    described_class.new.execute({user_id: user.id})

    expect(user.custom_fields[DiscourseAkismet::AKISMET_STATE_KEY]).to be_nil
  end

end
