# frozen_string_literal: true

describe 'MCP' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:mcp_token) { user.mcp_tokens.create!(name: 'Assistant') }

  it 'names the product in its server info', :multitenant do
    post '/mcp', headers: { 'Authorization' => "Bearer #{mcp_token.token}", 'Content-Type' => 'application/json' },
                 params: { jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }.to_json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('result', 'serverInfo', 'name')).to eq(Docuseal.product_name)
  end
end
