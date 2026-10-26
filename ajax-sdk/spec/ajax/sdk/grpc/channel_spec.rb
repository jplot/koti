# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength -- grpc integration specs set up a server, channel and handler

RSpec.describe Ajax::Sdk::Grpc::Channel do
  def string_field(number)
    Ajax::Sdk::Protobuf::Field.new(name: :value, number:, type: 9, label: 1, type_name: nil,
                                   oneof_index: nil, packed: false, proto3_optional: false)
  end

  let(:registry) do
    echo = Ajax::Sdk::Protobuf::Message.new(full_name: 'test.Echo', fields: [string_field(1)], oneofs: [],
                                            map_entry: false)
    reply = Ajax::Sdk::Protobuf::Message.new(full_name: 'test.Reply', fields: [string_field(1)], oneofs: [],
                                             map_entry: false)
    Ajax::Sdk::Protobuf::Registry.new({ 'test.Echo' => echo, 'test.Reply' => reply }, {})
  end
  let(:codec) { Ajax::Sdk::Protobuf::Codec.new(registry) }
  let(:rpcs) do
    rpc = Ajax::Sdk::Cloud::Rpc.new(path: '/test.Svc/call', type: :unary, request: 'test.Echo', response: 'test.Reply')
    Class.new do
      def initialize(rpc) = (@rpc = rpc)
      def rpc(_path) = @rpc
    end.new(rpc)
  end

  def frame(name, value) = [0, codec.encode(name, { value: }).bytesize].pack('CN') + codec.encode(name, { value: })
  def messages(body) = Ajax::Sdk::Grpc::MessageReader.new.push(body).map { |bytes| codec.decode('test.Echo', bytes) }

  def ok_headers = [%w[:status 200], ['content-type', 'application/grpc']]

  def channel_for(server)
    connection = Ajax::Sdk::Http2::Connection.new(TCPSocket.new('127.0.0.1', server.port))
    described_class.new(connection, authority: 'localhost', codec:, registry: rpcs)
  end

  it 'makes a unary call' do
    server = FakeHttp2Server.new do |_headers, body, responder|
      responder.respond(headers: ok_headers, data: frame('test.Reply', messages(body).first[:value].upcase),
                        trailers: [%w[grpc-status 0]])
    end
    channel = channel_for(server)

    expect(channel.unary('/test.Svc/call', { value: 'hi' })).to eq(value: 'HI')
  ensure
    server.stop
  end

  it 'yields each message of a server stream' do
    server = FakeHttp2Server.new do |_headers, _body, responder|
      responder.server.send_headers(responder.stream_id, ok_headers, end_stream: false)
      responder.server.send_body(responder.stream_id, frame('test.Reply', 'a') + frame('test.Reply', 'b'),
                                 end_stream: false)
      responder.server.send_headers(responder.stream_id, [%w[grpc-status 0]], end_stream: true)
    end
    channel = channel_for(server)

    collected = []
    channel.server_stream('/test.Svc/call', { value: 'go' }) { |message| collected << message[:value] }

    expect(collected).to eq(%w[a b])
  ensure
    server.stop
  end

  it 'sends a client stream and reads the answer' do
    server = FakeHttp2Server.new do |_headers, body, responder|
      joined = messages(body).map { |message| message[:value] }.join
      responder.respond(headers: ok_headers, data: frame('test.Reply', joined), trailers: [%w[grpc-status 0]])
    end
    channel = channel_for(server)

    answer = channel.client_stream('/test.Svc/call', [{ value: 'a' }, { value: 'b' }, { value: 'c' }])

    expect(answer).to eq(value: 'abc')
  ensure
    server.stop
  end

  it 'exchanges messages both ways on a bidi call' do
    server = FakeHttp2Server.new do |_headers, body, responder|
      responder.server.send_headers(responder.stream_id, ok_headers, end_stream: false)
      data = messages(body).map { |message| frame('test.Reply', message[:value].reverse) }.join
      responder.server.send_body(responder.stream_id, data, end_stream: false)
      responder.server.send_headers(responder.stream_id, [%w[grpc-status 0]], end_stream: true)
    end
    channel = channel_for(server)

    replies = []
    channel.bidi('/test.Svc/call') do |call|
      call.send(value: 'abc')
      call.send(value: 'xyz')
      call.close_send
      call.each { |message| replies << message[:value] }
    end

    expect(replies).to eq(%w[cba zyx])
  ensure
    server.stop
  end

  it 'raises Unauthenticated from trailers', :aggregate_failures do
    server = FakeHttp2Server.new do |_headers, _body, responder|
      responder.respond(headers: ok_headers, data: frame('test.Reply', 'x'), trailers: [%w[grpc-status 16]])
    end
    channel = channel_for(server)

    expect { channel.unary('/test.Svc/call', { value: 'hi' }) }
      .to raise_error(Ajax::Sdk::Grpc::Unauthenticated) { |error| expect(error.code).to eq(16) }
  ensure
    server.stop
  end

  it 'reads the status of a trailers-only answer' do
    server = FakeHttp2Server.new do |_headers, _body, responder|
      responder.server.send_headers(responder.stream_id, [%w[:status 200], %w[grpc-status 5]], end_stream: true)
    end
    channel = channel_for(server)

    expect { channel.unary('/test.Svc/call', { value: 'hi' }) }.to raise_error(Ajax::Sdk::Grpc::NotFound)
  ensure
    server.stop
  end

  it 'percent-decodes grpc-message' do
    server = FakeHttp2Server.new do |_headers, _body, responder|
      trailers = [%w[:status 200], %w[grpc-status 5], ['grpc-message', 'no%20space']]
      responder.server.send_headers(responder.stream_id, trailers, end_stream: true)
    end
    channel = channel_for(server)

    expect { channel.unary('/test.Svc/call', { value: 'hi' }) }
      .to raise_error(Ajax::Sdk::Grpc::NotFound, /no space/)
  ensure
    server.stop
  end

  it 'turns a closed connection into Unavailable' do
    server = FakeHttp2Server.new do |_headers, _body, responder|
      responder.server.send_headers(responder.stream_id, ok_headers, end_stream: false)
      responder.server.send_body(responder.stream_id, frame('test.Reply', 'one'), end_stream: false)
      responder.server.send_goaway(0)
    end
    channel = channel_for(server)

    expect { channel.server_stream('/test.Svc/call', { value: 'go' }) { |_message| nil } }
      .to raise_error(Ajax::Sdk::Grpc::Unavailable)
  ensure
    server.stop
  end
end
# rubocop:enable RSpec/ExampleLength
