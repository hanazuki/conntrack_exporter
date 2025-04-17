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

    PROTOCOLS = JSON.load_file(File.join(__dir__, '../iana/protocol-numbers.json')).transform_keys!(&:to_i)
    CONNLABELS = ->() do
      open('/etc/connlabels.conf') do |f|
        f.each_line(chomp: true).filter_map do |l|
          l.gsub!(/\#.*/)
          num, name = l.split(/\s+/, 2)
          next unless num && name
          [Integer(num), name]
        end.to_h
      end
    rescue Errno::ENOENT
      []
    end.call

    get '/metrics' do
      prom = Prometheus::Client::Registry.new
      collect_entries_stat(prom)
      collect_pcpu_stat(prom)

      content_type 'text/plain'
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

    private def l3proto_name(nfgen_family)
      case protonum = nfgen_family
      when 2; 'IPv4'
      when 10; 'IPv6'
      else nfgen_family
      end
    end

    private def l4proto_name(protonum)
      PROTOCOLS[protonum] || protonum.to_s
    end

    private def connlabel_name(bit)
      CONNLABELS[bit] || bit.to_s
    end

    private def collect_entries_stat(prom)
      entries = Prometheus::Client::Counter.new(:conntrack_entries, docstring: "Conntrack entries", labels: %i[l3proto l4proto])
      prom.register(entries)

      labelled_entries = Prometheus::Client::Counter.new(:conntrack_labelled_entries, docstring: "Conntrack labelled entries", labels: %i[l3proto l4proto label])
      prom.register(labelled_entries)


      Conntrack.open(&:dump_get).each do |msg|
        h = msg.to_h

        l3proto = l3proto_name(h[:nfgen_family])
        l4proto = l4proto_name(h.dig(:tuple_orig, :tuple_proto, :proto_num))
        connlabels = h[:labels]&.then do |str|
          str.unpack('c*').each_with_index.flat_map do |c, i|
            8.times.filter_map do |j|
              connlabel_name(i * 8 + j) if c[j] == 1
            end
          end
        end

        entries.increment(by: 1, labels: {l3proto:, l4proto:})
        connlabels&.each do |label|
          labelled_entries.increment(by: 1, labels: {l3proto:, l4proto:, label:})
        end
      end
    end
  end
end
