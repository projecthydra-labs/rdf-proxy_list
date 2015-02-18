require 'spec_helper'
require 'rdf/proxy_list'

describe RDF::ProxyList do
  subject { described_class.new(aggregator) }
  let(:aggregator) { RDF::URI('http://example.org/agg') }
  let(:uri) { RDF::URI('http://example.org') }

  RSpec::Matchers.define :have_ore_first_of do |expected|
    match do |actual|
      first = described_class.first_from_graph(actual.aggregator, actual.graph)
      first == expected
    end
  end

  RSpec::Matchers.define :have_ore_last_of do |expected|
    match do |actual|
      last = described_class.last_from_graph(actual.aggregator, actual.graph)
      last == expected
    end
  end

  RSpec::Matchers.define :have_ore_order_of do |*expected|
    match do |actual|
      current = described_class.first_from_graph(actual.aggregator,
                                                 actual.graph)
      expected.each do |item|
        return false unless current == item
        current = described_class.query_next_node(actual.graph, current)
      end
      true
    end
  end

  RSpec::Matchers.define :have_ore_proxy_in do |*expected|
    match do |actual|
      query = RDF::Query.new do
        pattern [:proxy, RDF::ORE.proxyIn, actual.aggregator]
        pattern [:proxy, RDF::ORE.proxyFor, :member]
      end

      members = query.execute(actual.graph).map(&:member)
      expected.each { |item| return false unless members.include? item }
    end
  end

  shared_context 'with uri list' do
    let(:uris) do
      uris = []
      10.times { |i| uris << RDF::URI('http://example.org') / i }
      uris
    end
  end

  shared_context 'with values' do
    include_context 'with uri list'
    before { subject.concat(uris) }
  end

  shared_context 'with a bad list graph' do
    let(:ns) { RDF::URI('http://example.org/') }
    let(:aggregator) { ns/:agg }
    let(:first) { ns/1 }
    let(:second) { ns/2 }
    let(:last) { ns/3 }
    let(:bad_graph) do
      # build a graph with two firsts and two lasts
      aggregator = ns/:agg
      graph = RDF::Graph.new

      first_proxy1 = RDF::URI.new(:b1)
      first_proxy2 = RDF::URI.new(:b1a)
      second_proxy = RDF::URI.new(:b2)
      last_proxy1 = RDF::URI.new(:b3)
      last_proxy2 = RDF::URI.new(:b3a)

      graph << [aggregator, RDF::IANA['first'], first_proxy1]
      graph << [first_proxy1, RDF::ORE['proxyFor'], first]
      graph << [first_proxy1, RDF::ORE['proxyIn'], aggregator]
      graph << [first_proxy1, RDF::IANA['next'], second_proxy]

      graph << [aggregator, RDF::IANA['first'], first_proxy2]
      graph << [first_proxy2, RDF::ORE['proxyFor'], first]
      graph << [first_proxy2, RDF::ORE['proxyIn'], aggregator]
      graph << [first_proxy2, RDF::IANA['next'], second_proxy]

      graph << [second_proxy, RDF::ORE['proxyFor'], second]
      graph << [second_proxy, RDF::IANA['prev'], first_proxy1]
      graph << [second_proxy, RDF::IANA['next'], last_proxy1]
      graph << [second_proxy, RDF::IANA['next'], last_proxy2]
      graph << [second_proxy, RDF::ORE['proxyIn'], aggregator]

      graph << [aggregator, RDF::IANA['last'], last_proxy1]
      graph << [last_proxy1, RDF::ORE['proxyFor'], last]
      graph << [last_proxy1, RDF::IANA['prev'], second_proxy]
      graph << [last_proxy1, RDF::ORE['proxyIn'], aggregator]

      graph << [aggregator, RDF::IANA['last'], last_proxy2]
      graph << [last_proxy2, RDF::ORE['proxyFor'], last]
      graph << [last_proxy2, RDF::IANA['prev'], second_proxy]
      graph << [last_proxy2, RDF::ORE['proxyIn'], aggregator]
      graph
    end
  end

  it 'will have an aggregator that is an RDF::Resource' do
    expect(subject.aggregator.to_uri).to eq('http://example.org/agg')
  end

  describe '.new' do
    subject { described_class.new(aggregator, graph) }

    context 'with empty graph' do
      let(:graph) { RDF::Graph.new }

      it 'initializes with empty list' do
        expect(subject).to be_empty
      end
    end

    context 'with graph without first node' do
      let(:graph) do
        RDF::Graph.new << RDF::Statement(RDF::Node.new, RDF::DC.title, 'moomin')
      end

      it 'initializes with empty list' do
        expect(subject).to be_empty
      end
    end

    context 'with graph with list items' do
      include_context 'with uri list'

      let(:graph) { described_class.new(aggregator).concat(uris).graph }

      it do
        expect(subject).to have_ore_order_of(*uris)
      end
    end
  end

  describe '.first_from_graph' do
    include_context 'with values'
    include_context 'with a bad list graph'

    let(:graph) { described_class.new(aggregator).concat(uris).graph }

    it 'returns the first item' do
      expect(
        described_class.first_from_graph(subject.aggregator, subject.graph)
      ).to eq uris.first
    end

    it 'raises error when more than one first is present' do
      expect {
        described_class.first_from_graph(aggregator, bad_graph)
      }.to raise_error RDF::ProxyList::InvalidProxyListGraph
    end

    it 'returns nil for empty list' do
      expect(
        described_class.first_from_graph(aggregator, RDF::Graph.new)
      ).to be_nil
    end
  end

  describe '.last_from_graph' do
    include_context 'with values'
    include_context 'with a bad list graph'

    let(:graph) { described_class.new(aggregator).concat(uris).graph }

    it 'returns the last item' do
      expect(
        described_class.last_from_graph(subject.aggregator, subject.graph)
      ).to eq uris.last
    end

    it 'raises error when more than one last is present' do
      expect {
        described_class.last_from_graph(aggregator, bad_graph)
      }.to raise_error RDF::ProxyList::InvalidProxyListGraph
    end

    it 'returns nil for empty list' do
      expect(
        described_class.last_from_graph(aggregator, RDF::Graph.new)
      ).to be_nil
    end
  end

  describe '.query_next_node' do
    include_context 'with a bad list graph'
    include_context 'with values'
    
    let(:graph) { described_class.new(aggregator).concat(uris).graph }
    
    it 'raises error when more than one next is present' do
      expect {
        described_class.query_next_node(bad_graph, second)
      }.to raise_error RDF::ProxyList::InvalidProxyListGraph
    end

    it 'raises nil when there is no next item' do
      expect(
        described_class.query_next_node(bad_graph, uris.last)
      ).to be_nil
    end
  end

  describe '#<<' do
    it 'accepts an RDF::URI' do
      expect { subject << uri }.to change { subject.count }.by(1)
    end

    it 'fails without an RDF::URI (is this correct?)' do
      expect { subject << 'http://google.com' }
        .to raise_error(subject.class::UnproxiableObjectError)
    end

    it 'allows you to push the same RDF::URI' do
      subject << uri
      expect { subject << uri }.to change { subject.count }.by(1)
    end
  end

  describe '#concat' do
    it 'pushes items to list' do
      expect { subject.concat([uri, uri, uri]) }
        .to change { subject.count }.by(3)
    end

    it 'returns self' do
      expect(subject.concat([uri, uri, uri])).to eq subject
    end
  end

  describe '#each' do
    include_context 'with values'

    it 'returns an enum' do
      expect(subject.each).to be_a Enumerator
    end

    it 'yields elements to block' do
      expect { |b| subject.each(&b) }.to yield_successive_args(*uris)
    end
  end

  describe '#graph' do
    let(:uri) { RDF::URI('http://example.org') }

    it 'will return a just in time RDF::Graph' do
      subject << uri
      original_graph = subject.graph
      subject << uri
      expect(subject.graph.object_id).to_not eq(original_graph.object_id)
    end

    context 'with one element' do
      before { subject << uri }

      it 'specifies first element' do
        expect(subject).to have_ore_first_of uri
      end

      it 'specifies last element' do
        expect(subject).to have_ore_last_of uri
      end
    end

    context 'with multiple elements' do
      include_context 'with values'

      it 'specifies last element' do
        expect(subject).to have_ore_first_of uris.first
      end

      it 'specifies last element' do
        expect(subject).to have_ore_last_of uris.last
      end

      it 'returns a graph with full order' do
        expect(subject).to have_ore_order_of(*uris)
      end

      it 'returns a graph with correct ORE.proxyIn ' do
        expect(subject).to have_ore_proxy_in(*uris)
      end
    end

    context 'with no elements' do
      it 'will return an empty graph' do
        expect(subject.graph.count).to eq(0)
      end
    end
  end

  describe 'RDF::Value compliance' do
    describe '#to_term' do
      it 'returns aggregator' do
        expect(subject.to_term).to eq aggregator
      end
    end
  end

  describe 'RDF::Enumerable compliance' do
    describe '#each_statement' do
      include_context 'with values'

      it 'returns an Enumerator over statements' do
        expect { |b| subject.each_statement(&b) }
          .to yield_control.exactly(subject.graph.count).times
      end
    end
  end
end

describe RDF::ProxyList::VERSION do
  let(:version_regex) { /^(\d+\.?){3,4}$/ }
  it 'has major' do
    expect(subject::MAJOR).not_to be_nil
  end

  it 'has minor' do
    expect(subject::MINOR).not_to be_nil
  end

  it 'has tiny' do
    expect(subject::TINY).not_to be_nil
  end

  describe '#to_s' do
    it 'returns a version string' do
      expect(subject.to_s).to match version_regex
    end
  end

  describe '#to_str' do
    it 'returns a version string' do
      expect(subject.to_str).to match version_regex
    end
  end

  describe '#to_a' do
    it 'returns an array' do
      expect(subject.to_a).to include(subject::MAJOR,
                                      subject::MINOR,
                                      subject::TINY)
    end
  end
end
