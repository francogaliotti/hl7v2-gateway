# frozen_string_literal: true

require_relative '../../examples/mock_api'

RSpec.describe MockApi do
  def request_document(service:, observations: [], type: 'ORM^O01')
    segments = [
      { 'segment' => 'MSH', 'fields' => { 'message_type' => type } },
      { 'segment' => 'OBR', 'fields' => { 'universal_service_identifier' => { '1' => service } } }
    ]
    segments += observations.map do |code, value, units|
      { 'segment' => 'OBX', 'fields' => { 'observation_identifier' => { '1' => code },
                                          'observation_value' => value, 'units' => units }.compact }
    end
    { 'message_type' => type, 'segments' => segments }
  end

  describe '.handle for a BMI order' do
    it 'calculates the index from kilograms and centimetres' do
      status, body = described_class.handle(request_document(service: 'BMI', observations: [['29463-7', '68.5', 'kg'],
                                                                                            ['8302-2', '172', 'cm']]))

      expect(status).to eq(200)
      expect(body['observations'].first).to include('identifier' => '39156-5', 'value' => 23.2, 'units' => 'kg/m2')
      expect(body['observations'].last).to include('value' => 'Normal')
    end

    it 'converts pounds and inches' do
      _status, body = described_class.handle(request_document(service: 'BMI', observations: [['WT', '150', 'lb'], ['HT', '65', 'in']]))

      expect(body['observations'].first['value']).to eq(25.0)
      expect(body['observations'].last['value']).to eq('Overweight')
    end

    it 'flags values outside the reference range' do
      _status, body = described_class.handle(request_document(service: 'BMI', observations: [['WT', '120', 'kg'], ['HT', '1.7', 'm']]))

      expect(body['observations'].first).to include('abnormal_flags' => 'A')
      expect(body['observations'].last['value']).to eq('Obese')
    end

    it 'answers 422 when a measurement is missing' do
      status, body = described_class.handle(request_document(service: 'BMI', observations: [['29463-7', '68.5', 'kg']]))

      expect(status).to eq(422)
      expect(body['error']).to match(/required/)
    end
  end

  describe '.handle for other messages' do
    it 'acknowledges ADT events' do
      expect(described_class.handle(request_document(service: 'X', type: 'ADT^A01')))
        .to eq([200, { 'message' => 'Patient event recorded' }])
    end

    it 'acknowledges anything else' do
      expect(described_class.handle(request_document(service: 'X'))).to eq([200, { 'message' => 'Message received' }])
    end
  end
end
