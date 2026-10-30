# frozen_string_literal: true

describe 'Features this edition does not serve' do
  # Test env raises exceptions (show_exceptions: :none), so call the exceptions app as production does.
  def error_response(path)
    env = Rack::MockRequest.env_for(path, 'HTTP_ACCEPT' => 'application/json',
                                          'action_dispatch.exception' => ActionController::RoutingError.new(path))

    status, _headers, body = Rails.application.config.exceptions_app.call(env)

    [status, JSON.parse(body.each.to_a.join)]
  end

  it 'answers 404 with a neutral message, without upstream pricing' do
    status, body = error_response('/api/templates/html')

    expect(status).to eq(404)
    expect(body).to eq('status' => 404, 'message' => 'This feature is not available on this instance.')
  end
end
