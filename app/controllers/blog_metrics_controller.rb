require 'net/http'
require 'rexml/document'
require 'mackerel/client'

class BlogMetricsController < ActionController::API
  BLOG_URL = ENV["BOOKMARK_COUNT_BLOG_URL"].freeze

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

    @mackerel = Mackerel::Client.new(mackerel_api_key: ENV["MACKEREL_API_KEY"])
    @mackerel.post_service_metrics(ENV["BOOKMARK_COUNT_SERVICE_NAME"], [{
        name: ENV["BOOKMARK_COUNT_METRIC_NAME"],
        time: Time.now.to_i,
        value: bookmark_count
    }])
    head 200
  end
end
