# frozen_string_literal: true

require 'socket'

RSpec.describe Ajax::Sdk::Sia::Receiver do
  subject(:receiver) do
    described_class.new(host: '127.0.0.1', port: 0, account: 'AAA', key:, timeband: [40, 20], &handler).start
  end

  let(:key) { nil }
  let(:events) { Queue.new }
  let(:handler) { ->(event) { events << event } }

  after { receiver.stop }

  def exchange(*frames)
    socket = TCPSocket.new('127.0.0.1', receiver.port)
    frames.map do |frame|
      socket.write(frame)
      socket.wait_readable(0.5) ? socket.gets("\r") : nil
    end
  ensure
    socket&.close
  end

  it 'acknowledges a frame and yields its event', :aggregate_failures do
    expect(exchange(sia_frame('"SIA-DCS"0084L0#AAA[#AAA|Nri1/XC12]'))).to eq([sia_frame('"ACK"0084L0#AAA[]')])
    expect(events.pop(timeout: 1))
      .to have_attributes(account: 'AAA', code: 'XC', group: '1', number: '12', label: be_a(String))
  end

  it 'answers DUH to an unknown account' do
    expect(exchange(sia_frame('"SIA-DCS"0001L0#BBB[#BBB|Nri1/XC12]'))).to eq([sia_frame('"DUH"0001L0#BBB[]')])
  end

  it 'answers NAK to a frame outside the time band', :aggregate_failures do
    late = sia_frame("\"SIA-DCS\"0002L0#AAA[#AAA|Nri1/BA3]#{sia_stamp(Time.now - 120)}")

    expect(exchange(late).first).to match(/"NAK"0000R0L0A0\[\]_\d\d:\d\d:\d\d,\d\d-\d\d-\d{4}\r\z/)
    expect(events).to be_empty
  end

  it 'answers NAK to a frame stamped further ahead than the time band allows', :aggregate_failures do
    early = sia_frame("\"SIA-DCS\"0013L0#AAA[#AAA|Nri1/BA3]#{sia_stamp(Time.now + 30)}")

    expect(exchange(early).first).to include('"NAK"')
    expect(events).to be_empty
  end

  it 'acknowledges a link test without an event', :aggregate_failures do
    expect(exchange(sia_frame('"NULL"0003L0#AAA[]'))).to eq([sia_frame('"ACK"0003L0#AAA[]')])
    expect(events).to be_empty
  end

  it 'stays silent and yields nothing on a corrupt frame, then serves the next one', :aggregate_failures do
    corrupt = sia_frame('"SIA-DCS"0004L0#AAA[#AAA|Nri1/BA3]').sub(/\A\n\h{4}/, "\n0000")

    expect(exchange(corrupt, sia_frame('"NULL"0005L0#AAA[]'))).to eq([nil, sia_frame('"ACK"0005L0#AAA[]')])
    expect(events).to be_empty
  end

  context 'with a key' do
    let(:key) { SiaFrames::KEY }

    it 'acknowledges an encrypted frame in kind and yields its event', :aggregate_failures do
      expect(exchange(encrypted_sia_frame('SIA-DCS', '#AAA|Nri1/BA3')).first).to include('"*ACK"0001R0L0#AAA[')
      expect(events.pop(timeout: 1)).to have_attributes(code: 'BA', group: '1', number: '3')
    end

    it 'answers NAK to an encrypted frame outside the time band', :aggregate_failures do
      late = encrypted_sia_frame('SIA-DCS', '#AAA|Nri1/BA3', time: Time.now - 120)

      expect(exchange(late).first).to include('"NAK"')
      expect(events).to be_empty
    end

    it 'answers DUH to a clear frame', :aggregate_failures do
      expect(exchange(sia_frame('"SIA-DCS"0006L0#AAA[#AAA|Nri1/BA3]'))).to eq([sia_frame('"DUH"0006L0#AAA[]')])
      expect(events).to be_empty
    end
  end

  it 'acknowledges a frame whose text is not UTF-8', :aggregate_failures do
    frame = sia_frame("\"SIA-DCS\"0009L0#AAA[#AAA|Nri1/BA3 Entr\xE9e]".b)

    expect(exchange(frame)).to eq([sia_frame('"ACK"0009L0#AAA[]')])
    expect(events.pop(timeout: 1)).to have_attributes(code: 'BA')
  end

  context 'when the block raises' do
    let(:started) { Queue.new }
    let(:threads) { Queue.new }
    let(:handler) do
      lambda do |event|
        case event.number
        when '1' then raise('handler bug')
        when '2' then raise(IOError, 'handler io')
        when '3'
          started << event
          sleep(0.3)
          raise('late handler bug')
        end
      end
    end

    before do
      allow(Thread).to receive(:new).and_wrap_original do |original, &body|
        original.call do
          threads << Thread.current
          Thread.current.report_on_exception = false
          body.call
        end
      end
    end

    def raised(number)
      socket = TCPSocket.new('127.0.0.1', receiver.port)
      socket.write(sia_frame("\"SIA-DCS\"0010L0#AAA[#AAA|Nri1/BA#{number}]"))
      [socket.gets("\r"), socket.wait_readable(1) && socket.read]
    ensure
      socket&.close
    end

    it 'leaves the error to the thread of that connection, which it ends', :aggregate_failures do
      expect(raised(1)).to eq([sia_frame('"ACK"0010L0#AAA[]'), ''])
      expect { Array.new(2) { threads.pop }.last.join(1) }.to raise_error(RuntimeError, 'handler bug')
    end

    it 'leaves an IOError of the block to its thread too', :aggregate_failures do
      expect(raised(2)).to eq([sia_frame('"ACK"0010L0#AAA[]'), ''])
      expect { Array.new(2) { threads.pop }.last.join(1) }.to raise_error(IOError, 'handler io')
    end

    it 'closes every connection when a block raises while it stops', :aggregate_failures do
      first, second = Array.new(2) { |n| TCPSocket.new('127.0.0.1', receiver.port).tap { link_test(it, 30 + n) } }
      first.write(sia_frame('"SIA-DCS"0011L0#AAA[#AAA|Nri1/BA3]'))
      started.pop(timeout: 1)

      expect { receiver.stop }.not_to raise_error
      expect(second.wait_readable(1) && second.read).to eq('')
    ensure
      [first, second].each { it&.close }
    end
  end

  it 'keeps accepting after a failed accept' do
    allow(TCPServer).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |server| fail_first_accept(server) }
    end

    expect(exchange(sia_frame('"NULL"0012L0#AAA[]'))).to eq([sia_frame('"ACK"0012L0#AAA[]')])
  end

  def fail_first_accept(server)
    failed = false
    allow(server).to receive(:accept).and_wrap_original do |accept|
      failed ? accept.call : (failed = true) && raise(Errno::EMFILE)
    end
  end

  it 'closes the oldest connection of a peer that opens more than eight', :aggregate_failures do
    open = Array.new(8) { |n| TCPSocket.new('127.0.0.1', receiver.port).tap { link_test(it, n) } }

    expect(exchange(sia_frame('"NULL"0099L0#AAA[]'))).to eq([sia_frame('"ACK"0099L0#AAA[]')])
    expect(open.first.wait_readable(1) && open.first.read).to eq('')
    expect(link_test(open.last, 50)).to eq(sia_frame('"ACK"0050L0#AAA[]'))
  ensure
    open&.each(&:close)
  end

  def link_test(socket, number)
    socket.write(sia_frame(%("NULL"#{format('%04d', number)}L0#AAA[])))
    socket.wait_readable(1) && socket.gets("\r")
  end

  it 'stops while a hub keeps its connection open', :aggregate_failures do
    socket = TCPSocket.new('127.0.0.1', receiver.port)
    socket.write(sia_frame('"NULL"0007L0#AAA[]'))
    socket.gets("\r")

    expect(Thread.new { receiver.stop }.join(2)).to be_a(Thread)
    expect(socket.wait_readable(1) && socket.read).to eq('')
  ensure
    socket&.close
  end

  it 'serves concurrent hubs, yielding each event once and acknowledging each frame in order', :aggregate_failures do
    batches = Array.new(8) { |hub| Array.new(25) { hub_frame(hub, it) } }

    acks = batches.map { |batch| Thread.new { send_in_pieces(batch) } }.map(&:value)
    received = Array.new(200) { events.pop(timeout: 2)&.then { [it.group, it.number] } }

    expect(acks).to eq(batches.map { |batch| batch.map { ack_for(it) } })
    expect(received.compact.sort).to eq(Array.new(8) { |hub| Array.new(25) { [hub.to_s, it.to_s] } }.flatten(1).sort)
    expect(events).to be_empty
  end

  def hub_frame(hub, number) = sia_frame(%("SIA-DCS"#{format('%04d', number)}L0#AAA[#AAA|Nri#{hub}/BA#{number}]))

  def send_in_pieces(batch)
    socket = TCPSocket.new('127.0.0.1', receiver.port)
    bytes = batch.join
    bytes = bytes[(socket.write(bytes[0, rand(1..40)]))..] until bytes.empty?
    Array.new(batch.size) { socket.wait_readable(2) && socket.gets("\r") }
  ensure
    socket&.close
  end

  def ack_for(frame) = sia_frame(%("ACK"#{frame[/"SIA-DCS"(\d{4})/, 1]}L0#AAA[]))
end
