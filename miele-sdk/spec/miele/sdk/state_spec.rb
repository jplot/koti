# frozen_string_literal: true

RSpec.describe Miele::Sdk::State do
  subject(:state) { described_class.new(raw, device_type) }

  let(:device_type) { :oven_microwave }
  let(:raw) do
    { 'Status' => 1, 'ProgramType' => 1, 'ProgramPhase' => 3329, 'RemainingTime' => [1, 30],
      'ElapsedTime' => [0, 5], 'StartTime' => [2, 0], 'Temperature' => [18_050, -32_768, -32_768],
      'TargetTemperature' => [18_000, -32_768, -32_768], 'SignalDoor' => true, 'SignalFailure' => false,
      'RemoteEnable' => [15, 0, 0], 'Light' => 1 }
  end

  it 'reads the status of an appliance that is off' do
    expect(state.status).to eq(:off)
  end

  it 'names the statuses the Miele app adds to the specification' do
    statuses = [144, 145, 147].map { described_class.new({ 'Status' => it }, device_type).status }
    expect(statuses).to eq(%i[default locked running_background])
  end

  it 'leaves status 148 unknown outside hoods' do
    expect(described_class.new({ 'Status' => 148 }, device_type).status).to eq(:unknown)
  end

  it 'converts remaining time to seconds' do
    expect(state.remaining_time).to eq(5400)
  end

  it 'reads a time sent as plain minutes' do
    raw['RemainingTime'] = 90
    expect(state.remaining_time).to eq(5400)
  end

  it 'converts elapsed and start times to seconds' do
    expect([state.elapsed_time, state.start_time]).to eq([300, 7200])
  end

  it 'names the program type and the phase of its family' do
    expect([state.program_type, state.program_phase]).to eq(%i[own_program heating_up_phase])
  end

  it 'numbers program types from 1 on DOP2 appliances, as the Miele app reads them' do
    types = [1, 2, 6].map { described_class.new({ 'ProgramType' => it }, :oven, protocol_version: 4).program_type }
    expect(types).to eq(%i[normal_operation own_program helper_program])
  end

  it 'numbers program types from 0 on Dop1 appliances, up to the helper program' do
    types = [0, 4, 5].map { described_class.new({ 'ProgramType' => it }, :hood, protocol_version: 2).program_type }
    expect(types).to eq(%i[normal_operation customer_service_program helper_program])
  end

  it 'converts temperatures to Celsius and keeps absent ones as nil' do
    expect([state.temperatures, state.target_temperatures]).to eq([[180.5, nil, nil], [180.0, nil, nil]])
  end

  it 'reads the door, failure, remote control and light signals' do
    expect([state.door_open?, state.failure?, state.remote_control?, state.light]).to eq([true, false, true, :on])
  end

  context 'with a hood' do
    let(:device_type) { :hood }
    let(:raw) { { 'Status' => 5, 'ProgramPhase' => 4608, 'RemoteEnable' => [9, 0, 0], 'VentilationStep' => 3 } }

    it 'reads its ventilation step' do
      expect([state.status, state.ventilation_step, state.remote_control?]).to eq([:running, 3, true])
    end

    it 'reads status 148 as ready' do
      raw['Status'] = 148
      expect(state.status).to eq(:ready)
    end

    it 'names its phase from the hood table' do
      phases = [4608, 4613].map { described_class.new({ 'ProgramPhase' => it }, device_type).program_phase }
      expect(phases).to eq(%i[not_running delayed_shutdown])
    end
  end

  context 'with a hob' do
    let(:device_type) { :hob_induction }
    let(:raw) do
      { 'RemoteEnable' => [0, 0, 0], 'PlateStep' => [4, 0], 'PlateRemainingHeat' => [0, 2],
        'PlateRemainingMinutes' => [12, 0], 'PlateElapsedMinutes' => [3, 0], 'PlateTimerSeconds' => [720, 0] }
    end

    it 'reads each plate', :aggregate_failures do
      expect(state.plates.first).to have_attributes(step: 4, remaining_heat: 0, remaining_minutes: 12,
                                                    elapsed_minutes: 3, timer_seconds: 720)
      expect(state.plates.last).to have_attributes(step: 0, remaining_heat: 2)
      expect(state.remote_control?).to be(false)
    end

    it 'maps a phase without a published table to :unknown' do
      expect(described_class.new({ 'ProgramPhase' => 4608 }, device_type).program_phase).to eq(:unknown)
    end
  end
end
