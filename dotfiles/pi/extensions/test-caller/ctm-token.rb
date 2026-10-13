raise 'Development Rails only' unless Rails.env.development?
account_id = Integer(ENV.fetch('TEST_CALLER_CTM_ACCOUNT_ID'), 10)
account_sid = ENV.fetch('TEST_CALLER_ACCOUNT_SID')
application_sid = ENV.fetch('TEST_CALLER_APPLICATION_SID')
identity = ENV.fetch('TEST_CALLER_IDENTITY')
raise 'Invalid account SID' unless /\AAC[0-9a-f]{32}\z/i.match?(account_sid)
raise 'Invalid application SID' unless /\AAP[0-9a-f]{32}\z/i.match?(application_sid)
raise 'Invalid caller identity' unless /\A[a-z0-9_-]{1,64}\z/i.match?(identity)
ActiveRecord::Base.connection.execute('SET TRANSACTION READ ONLY')
ActiveRecord::Base.transaction do
  account = Account.find(account_id)
  raise 'Configured account differs from dev account' unless account.account_sid == account_sid
  raise 'Dev account is inactive' unless account.active?
  app = TwilioApp.find_by!(account_id: account.id)
  raise 'A dedicated fixed-route caller application is required' if app.outbound_sid == application_sid
  raise 'Existing Voice SDK key is unavailable' unless /\ASK[0-9a-f]{32}\z/i.match?(app.api_key.to_s) && app.api_sec.present?
  grant = Twilio::JWT::AccessToken::VoiceGrant.new
  grant.outgoing_application_sid = application_sid
  token = Twilio::JWT::AccessToken.new(account_sid, app.api_key, app.api_sec, [grant], identity: identity, ttl: 600)
  puts "TEST_CALLER_TOKEN=#{token.to_jwt}"
end
