# frozen_string_literal: true

describe 'Link previews' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:) }
  let(:submitter) { create(:submission, :with_submitters, template:, created_by_user: author).submitters.first }

  it "previews a signer's link with the product image" do
    get submit_form_path(slug: submitter.slug)

    html = Nokogiri::HTML(response.body)

    expect(response).to have_http_status(:ok)
    expect(html.css('meta[property="og:image"], meta[name="twitter:image"]').pluck('content'))
      .to eq(["#{root_url}preview.png"] * 2)
    expect(html.css('meta[property="og:image:width"], meta[property="og:image:height"]').pluck('content'))
      .to eq(%w[800 800])
  end

  it 'serves the Findem mark at the declared size, without the upstream wordmark' do
    image = Vips::Image.new_from_file(Rails.public_path.join('preview.png').to_s).extract_band(0, n: 3)

    expect([image.width, image.height]).to eq([800, 800])
    expect((image == [233, 207, 59]).bandand.max).to eq(255)
    expect((image == [44, 24, 55]).bandand.max).to eq(0)
  end
end
