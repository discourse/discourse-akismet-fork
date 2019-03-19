require 'rails_helper'

RSpec.describe DiscourseAkismet::AdminModQueueController do
  let(:admin) { Fabricate(:admin) }
  let(:a_post) { Fabricate(:post) }

  before do
    sign_in(admin)
    SiteSetting.akismet_enabled = true
    PostCustomField.create!(post: a_post, name: "AKISMET_STATE", value: "needs_review")
  end

  it "should include a post with excerpt" do
    get "/admin/plugins/akismet/index.json"
    expect(response.status).to eq(200)

    data = JSON.parse(response.body)
    expect(data["posts"][0]).to include("excerpt")
  end

  describe 'Reviewing posts with the new Reviewable API', if: defined?(Reviewable) do
    shared_examples 'It uses the new Reviewable API or fallbacks to the existing behaviour' do
      it 'successfully calls allow' do
        post('/admin/plugins/akismet/allow.json', params: { post_id: a_post.id })

        expect(response.code).to eq('200')
      end

      it 'successfully calls confirm_spam' do
        post('/admin/plugins/akismet/confirm_spam.json', params: { post_id: a_post.id })

        expect(response.code).to eq('200')
      end

      it 'successfully calls dismiss' do
        post('/admin/plugins/akismet/dismiss.json', params: { post_id: a_post.id })

        expect(response.code).to eq('200')
      end

      it 'successfully calls delete_user' do
        delete('/admin/plugins/akismet/delete_user.json', params: { post_id: a_post.id })

        expect(response.code).to eq('200')
      end
    end

    context 'When the API is defined and the Reviewable exists' do
      before do
        ReviewableAkismetPost.needs_review!(target: a_post, created_by: a_post.user)
      end

      it_behaves_like 'It uses the new Reviewable API or fallbacks to the existing behaviour'
    end

    context 'When the API is defined but we did not migrate our current data' do
      it_behaves_like 'It uses the new Reviewable API or fallbacks to the existing behaviour'
    end

  end
end
