require 'ynl'
require 'prometheus/client'
require 'prometheus/client/formats/text'

require_relative 'conntrack_exporter/version'

require 'sinatra/base'

Conntrack = Ynl::Family.build(File.join(__dir__, '../linux/conntrack.yaml'))

module ConntrackExporter
  class App < Sinatra::Base
    set :host_authorization, { permitted_hosts: [] }

    PCPU_METRICS = Conntrack::AttributeSets::ConntrackStatsAttrs::BY_NAME.keys.freeze

    get '/metrics' do
      prom = Prometheus::Client::Registry.new
      collect_pcpu_stat(prom)

      content_type 'text/plain; version=0.0.4'
      Prometheus::Client::Formats::Text.marshal(prom)
    end

    private def collect_pcpu_stat(prom)
      counters = PCPU_METRICS.to_h do |metric|
        counter = Prometheus::Client::Counter.new(:"conntrack_#{metric}_total", docstring: "Conntrack #{metric}", labels: %i[cpu])
        prom.register(counter)
        [metric, counter]
      end

      Conntrack.open(&:dump_get_stats).each do |msg|
        h = msg.to_h
        cpu = h[:res_id]

        counters.each do |metric, counter|
          if val = h[metric]
            counter.increment(by: val, labels: {cpu:})
          end
        end
      end
    end
  end
end
