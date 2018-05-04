require 'net/http'
require 'rexml/document'
require 'mackerel/client'
require 'google/api_client'

class BlogMetricsController < ActionController::API
  SEND_FREQUENCY_MIN = 15

  BLOG_URL = ENV["BOOKMARK_COUNT_BLOG_URL"].freeze
  HATEDA_RSS = (ENV["SUBSCRIBERS_HATEDA_URL"] + 'rss').freeze
  HATEBLO_FEED = (ENV["BOOKMARK_COUNT_BLOG_URL"] + 'feed').freeze
  HATEBLO_RSS = (ENV["BOOKMARK_COUNT_BLOG_URL"] + 'rss').freeze

  LDR_ENDPOINT = 'http://rpc.reader.livedoor.com/count?feedlink='.freeze

  DUMMY_UA = 'Opera/9.80 (Windows NT 5.1; U; ja) Presto/2.7.62 Version/11.01'.freeze

  def count_bookmarks
    response = Net::HTTP.new('b.hatena.ne.jp').start do |http|
      request = <<EOS
<?xml version="1.0"?>
<methodCall>
  <methodName>bookmark.getTotalCount</methodName>
  <params>
    <param>
      <value><string>#{BLOG_URL}</string></value>
    </param>
  </params>
</methodCall>
EOS
      header = {
        'Content-Type'   => 'text/xml; charset=utf-8',
        'Content-Length' => request.bytesize.to_s,
        'User-Agent'     => DUMMY_UA,
      }
      http.request_post('/xmlrpc', request, header)
    end

    doc = REXML::Document.new(response.body)
    bookmark_count = doc.elements['/methodResponse/params/param/value/int'].text.to_i

    mackerel = Mackerel::Client.new(mackerel_api_key: ENV["MACKEREL_API_KEY"])
    mackerel.post_service_metrics(ENV["BOOKMARK_COUNT_SERVICE_NAME"], [{
        name: ENV["BOOKMARK_COUNT_METRIC_NAME"],
        time: Time.now.to_i,
        value: bookmark_count
    }])
    head 200
  end

  def count_subscribers
    head 200 unless every_15min?

    ldr_hateda = ldr_check(Net::HTTP.get(URI.parse(LDR_ENDPOINT + HATEDA_RSS)).to_i)
    ldr_hateblo_feed = ldr_check(Net::HTTP.get(URI.parse(LDR_ENDPOINT + HATEBLO_FEED)).to_i)
    ldr_hateblo_rss  = ldr_check(Net::HTTP.get(URI.parse(LDR_ENDPOINT + HATEBLO_RSS)).to_i)

    # http://cloud.feedly.com/v3/feeds/feed%2Fhttp%3A%2F%2Fd.hatena.ne.jp%2Fa-know%2Frss
    feedly_hateda = JSON.parse(Net::HTTP.get(URI.parse(feedly_target(HATEDA_RSS))))['subscribers']
    feedly_hateblo_feed = JSON.parse(Net::HTTP.get(URI.parse(feedly_target(HATEBLO_FEED))))['subscribers']
    feedly_hateblo_rss  = JSON.parse(Net::HTTP.get(URI.parse(feedly_target(HATEBLO_RSS))))['subscribers']

    hateblo_subscribers_response = Net::HTTP.get(URI.parse(ENV["HATEBLO_SUBSCRIBE_BUTTON"] + 'subscribe/iframe'))
    hateblo_subscribers_response =~ /data-subscribers-count="(\d+)"/
    hateblo_subscribers = $1.to_i

    total_subscribers = ldr_hateda +
                        ldr_hateblo_feed +
                        ldr_hateblo_rss +
                        feedly_hateda +
                        feedly_hateblo_feed +
                        feedly_hateblo_rss +
                        hateblo_subscribers

    post_time = Time.now.to_i
    mackerel = Mackerel::Client.new(mackerel_api_key: ENV["MACKEREL_API_KEY"])
    mackerel.post_service_metrics(ENV["SUBSCRIBERS_COUNT_SERVICE_NAME"],
      [
        { name: ENV["TOTAL_SUBSCRIBERS_COUNT_METRIC_NAME"], time: post_time, value: total_subscribers },
        { name: ENV["LDR_HATEDA_SUBSCRIBERS_COUNT_METRIC_NAME"], time: post_time, value: ldr_hateda },
        { name: ENV["LDR_HATEBLO_SUBSCRIBERS_COUNT_METRIC_NAME"], time: post_time, value: ldr_hateblo_feed },
        { name: ENV["LDR_HATEBLO_RSS_SUBSCRIBERS_COUNT_METRIC_NAME"], time: post_time, value: ldr_hateblo_rss },
        { name: ENV["FEEDLY_HATEDA_SUBSCRIBERS_COUNT_METRIC_NAME"], time: post_time, value: feedly_hateda },
        { name: ENV["FEEDLY_HATEBLO_SUBSCRIBERS_COUNT_METRIC_NAME"], time: post_time, value: feedly_hateblo_feed },
        { name: ENV["FEEDLY_HATEBLO_RSS_SUBSCRIBERS_COUNT_METRIC_NAME"], time: post_time, value: feedly_hateblo_rss },
        { name: ENV["HATEBLO_SUBSCRIBERS_COUNT_METRIC_NAME"], time: post_time, value: hateblo_subscribers },
      ])

    head 200
  end

  # see https://github.com/a-know/a-know-dashing/blob/master/jobs/visitor_count_real_time.rb
  def count_active_visitors

    # Update these to match your own apps credentials
    service_account_email = ENV['SERVICE_ACCOUNT_EMAIL'] # Email of service account
    profile_id = ENV['PROFILE_ID'] # Analytics profile ID.

    # Get the Google API client
    client = Google::APIClient.new(
      :application_name => ENV['APPLICATION_NAME'],
      :application_version => '0.01'
    )

    key = OpenSSL::PKey::RSA.new(ENV['GOOGLE_API_KEY'].gsub("\\n", "\n"))
    client.authorization = Signet::OAuth2::Client.new(
      :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
      :audience             => 'https://accounts.google.com/o/oauth2/token',
      :scope                => 'https://www.googleapis.com/auth/analytics.readonly',
      :issuer               => service_account_email,
      :signing_key          => key,
    )

    # Request a token for our service account
    client.authorization.fetch_access_token!

    # Get the analytics API
    analytics = client.discovered_api('analytics','v3')

    # Execute the query, get the value `[["1"]]`
    response = client.execute(:api_method => analytics.data.realtime.get, :parameters => {
      'ids' => "ga:" + profile_id,
      'metrics' => "ga:activeVisitors",
    }).data.rows

    number = response.empty? ? 0 : response.first.first.to_i

    mackerel = Mackerel::Client.new(mackerel_api_key: ENV["MACKEREL_API_KEY"])
    mackerel.post_service_metrics(ENV["ACTIVE_VISITOR_SERVICE_NAME"], [{
        name: ENV["ACTIVE_VISITOR_METRIC_NAME"],
        time: Time.now.to_i,
        value: number
    }])
    head 200
  end

  private

  def every_15min?
    min = DateTime.now.min
    min % SEND_FREQUENCY_MIN == 0
  end

  def ldr_check(count)
    count < 0 ? 0 : count
  end

  def feedly_target(rss_url)
    'http://cloud.feedly.com/v3/feeds/' + URI.escape("feed/#{rss_url}", ':/')
  end
end
