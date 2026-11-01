# frozen_string_literal: true

# Plain-text gRPC server standing in for the mobile gateway. A script gives, for each path, the calls it answers in
# turn: a server stream sends each Hash of its call as a response, raising a gRPC error found among them, then ends,
# or stays open at +:open+; a unary call answers its one Hash. A bidi call plays its steps the same way, and waits
# for the client's next request at +:read+. A stream past the end of its script stays open until
# the client leaves or the server stops. +closed+ receives the path of each stream as it closes, and +requests+
# gives every request received so far, with its path.
class FakeGateway
  # grpc logs each reply with to_s, which crashes google-protobuf 4.36 on a message of the shipped pool holding a
  # sub-message: replies go out already encoded.
  Encoded = Data.define(:bytes) do
    def self.encode(reply) = reply.bytes
  end

  # A server learns that a client left only when a write fails: an open stream writes this every 50 ms.
  KEEPALIVE = { success: {} }.freeze

  attr_reader :port, :closed

  # @param script [Hash{String=>Array}, String] the calls by path, or one streaming path for +count+ empty successes
  def self.start(script, count: nil, pause: 0, first: [])
    script = { script => [[*first, *Array.new(count) { KEEPALIVE }]] } if count
    new(script, pause:).tap(&:start)
  end

  def initialize(script, pause: 0)
    @script = script.transform_values(&:dup)
    @pause = pause
    @closed = Queue.new
    @requests = []
    @lock = Mutex.new
    @stopping = false
  end

  def start
    @server = GRPC::RpcServer.new(pool_size: 10)
    @port = @server.add_http2_port('127.0.0.1:0', :this_port_is_insecure)
    @script.keys.group_by { it.split('/')[1] }.each { |name, paths| @server.handle(service(name, paths).new) }
    Thread.new { @server.run }
    @server.wait_till_running
  end

  def stop
    @stopping = true
    @server.stop
  end

  def answer(path, klass, request, streaming)
    @lock.synchronize { @requests << [path, request.to_h] }
    call = @script.fetch(path).shift
    return encoded(klass, call || KEEPALIVE) unless streaming

    Enumerator.new do |out|
      stream(klass, call, out)
    ensure
      @closed << path
    end
  end

  def converse(path, klass, requests)
    call = @script.fetch(path).shift
    Enumerator.new do |out|
      (call || [:open]).each do |step|
        next stream(klass, [step], out) unless step == :read

        request = requests.next.to_h
        @lock.synchronize { @requests << [path, request] }
      end
    ensure
      @closed << path
    end
  end

  def requests = @lock.synchronize { @requests.dup }

  private

  def stream(klass, call, out)
    (call || [:open]).each do |reply|
      next keep_open(klass, out) if reply == :open

      out << encoded(klass, reply)
      sleep(@pause)
    end
  end

  def keep_open(klass, out)
    until @stopping
      out << encoded(klass, KEEPALIVE)
      sleep(0.05)
    end
  end

  def encoded(klass, reply)
    raise reply if reply.is_a?(Exception)

    Encoded.new(klass.encode(klass.new(reply)))
  end

  def service(name, paths)
    klass = Class.new do
      include GRPC::GenericService

      self.marshal_class_method = :encode
      self.unmarshal_class_method = :decode
      self.service_name = name
    end
    paths.each { Ajax::Sdk::Cloud::Schemas.rpc(it).type == :bidi ? define_bidi(klass, it) : define_rpc(klass, it) }
    klass
  end

  def define_rpc(klass, path)
    gateway = self
    table = Ajax::Sdk::Cloud::Schemas.rpc(path)
    request, answer = [table.request, table.response].map { Ajax::Sdk::Cloud::Schemas.message(it) }
    streaming = table.type == :server_stream
    method = path.split('/').last
    klass.rpc(method.to_sym, request, streaming ? klass.stream(answer) : answer)
    klass.define_method(GRPC::GenericService.underscore(method)) { |req, _| gateway.answer(path, answer, req, streaming) }
  end

  def define_bidi(klass, path)
    gateway = self
    table = Ajax::Sdk::Cloud::Schemas.rpc(path)
    request, answer = [table.request, table.response].map { Ajax::Sdk::Cloud::Schemas.message(it) }
    method = path.split('/').last
    klass.rpc(method.to_sym, klass.stream(request), klass.stream(answer))
    klass.define_method(GRPC::GenericService.underscore(method)) { |reqs, _| gateway.converse(path, answer, reqs) }
  end
end
