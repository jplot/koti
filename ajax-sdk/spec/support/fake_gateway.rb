# frozen_string_literal: true

# Plain-text gRPC server standing in for the mobile gateway on one server-streaming method: it streams
# +count+ answers holding an empty success, +pause+ seconds apart, and pushes true to +closed+ once it stops.
class FakeGateway
  # grpc logs each reply with to_s, which crashes google-protobuf 4.36 on a message of the shipped pool holding a
  # sub-message: replies go out already encoded.
  Encoded = Data.define(:bytes) do
    def self.encode(reply) = reply.bytes
  end

  attr_reader :port, :closed

  def self.start(path, count:, pause:) = new(path, count:, pause:).tap(&:start)

  def initialize(path, count:, pause:)
    @closed = Queue.new
    @service = streaming_service(path, count, pause)
  end

  def start
    @server = GRPC::RpcServer.new(pool_size: 2)
    @port = @server.add_http2_port('127.0.0.1:0', :this_port_is_insecure)
    @server.handle(@service.new)
    Thread.new { @server.run }
    @server.wait_till_running
  end

  def stop = @server.stop

  private

  def streaming_service(path, count, pause)
    table = Ajax::Sdk::Cloud::Schemas.rpc(path)
    request, answer = [table.request, table.response].map { Ajax::Sdk::Cloud::Schemas.message(it) }
    service(path.split('/')[1], request, answer, replies(answer, count, pause))
  end

  def replies(answer, count, pause)
    lambda do
      Enumerator.new do |out|
        count.times { (out << Encoded.new(answer.encode(answer.new(success: {})))) && sleep(pause) }
      ensure
        @closed << true
      end
    end
  end

  def service(name, request, answer, replies)
    Class.new do
      include GRPC::GenericService

      self.marshal_class_method = :encode
      self.unmarshal_class_method = :decode
      self.service_name = name
      rpc :execute, request, stream(answer)
      define_method(:execute) { |*| replies.call }
    end
  end
end
