# frozen_string_literal: true

module Hl7Gateway
  # Human-friendly names for the fields of the most common segments (HL7 v2.5).
  #
  # Any field that is not listed here, and every field of a segment that is not listed at
  # all, is exposed as `field_<position>`, so nothing is ever dropped from a message.
  module Schema
    FIELD_NAMES = {
      'MSH' => {
        1 => 'field_separator', 2 => 'encoding_characters', 3 => 'sending_application', 4 => 'sending_facility',
        5 => 'receiving_application', 6 => 'receiving_facility', 7 => 'message_datetime', 8 => 'security',
        9 => 'message_type', 10 => 'message_control_id', 11 => 'processing_id', 12 => 'version_id',
        13 => 'sequence_number', 14 => 'continuation_pointer', 15 => 'accept_acknowledgment_type',
        16 => 'application_acknowledgment_type', 17 => 'country_code', 18 => 'character_set',
        19 => 'principal_language', 20 => 'alternate_character_set_handling_scheme',
        21 => 'message_profile_identifier'
      },
      'MSA' => {
        1 => 'acknowledgment_code', 2 => 'message_control_id', 3 => 'text_message',
        4 => 'expected_sequence_number', 5 => 'delayed_acknowledgment_type', 6 => 'error_condition'
      },
      'ERR' => {
        1 => 'error_code_and_location', 2 => 'error_location', 3 => 'hl7_error_code', 4 => 'severity',
        5 => 'application_error_code', 6 => 'application_error_parameter', 7 => 'diagnostic_information',
        8 => 'user_message', 9 => 'inform_person_indicator', 10 => 'override_type',
        11 => 'override_reason_code', 12 => 'help_desk_contact_point'
      },
      'EVN' => {
        1 => 'event_type_code', 2 => 'recorded_datetime', 3 => 'planned_event_datetime',
        4 => 'event_reason_code', 5 => 'operator_id', 6 => 'event_occurred', 7 => 'event_facility'
      },
      'PID' => {
        1 => 'set_id', 2 => 'patient_id', 3 => 'patient_identifier_list', 4 => 'alternate_patient_id',
        5 => 'patient_name', 6 => 'mothers_maiden_name', 7 => 'date_of_birth', 8 => 'administrative_sex',
        9 => 'patient_alias', 10 => 'race', 11 => 'patient_address', 12 => 'county_code', 13 => 'home_phone',
        14 => 'business_phone', 15 => 'primary_language', 16 => 'marital_status', 17 => 'religion',
        18 => 'patient_account_number', 19 => 'ssn_number', 20 => 'drivers_license_number',
        21 => 'mothers_identifier', 22 => 'ethnic_group', 23 => 'birth_place', 24 => 'multiple_birth_indicator',
        25 => 'birth_order', 26 => 'citizenship', 27 => 'veterans_military_status', 28 => 'nationality',
        29 => 'patient_death_datetime', 30 => 'patient_death_indicator'
      },
      'NK1' => {
        1 => 'set_id', 2 => 'name', 3 => 'relationship', 4 => 'address', 5 => 'phone_number',
        6 => 'business_phone_number', 7 => 'contact_role', 8 => 'start_date', 9 => 'end_date', 10 => 'job_title'
      },
      'PV1' => {
        1 => 'set_id', 2 => 'patient_class', 3 => 'assigned_patient_location', 4 => 'admission_type',
        5 => 'preadmit_number', 6 => 'prior_patient_location', 7 => 'attending_doctor', 8 => 'referring_doctor',
        9 => 'consulting_doctor', 10 => 'hospital_service', 11 => 'temporary_location',
        12 => 'preadmit_test_indicator', 13 => 'readmission_indicator', 14 => 'admit_source',
        15 => 'ambulatory_status', 16 => 'vip_indicator', 17 => 'admitting_doctor', 18 => 'patient_type',
        19 => 'visit_number', 20 => 'financial_class', 44 => 'admit_datetime', 45 => 'discharge_datetime'
      },
      'ORC' => {
        1 => 'order_control', 2 => 'placer_order_number', 3 => 'filler_order_number', 4 => 'placer_group_number',
        5 => 'order_status', 6 => 'response_flag', 7 => 'quantity_timing', 8 => 'parent_order',
        9 => 'datetime_of_transaction', 10 => 'entered_by', 11 => 'verified_by', 12 => 'ordering_provider',
        13 => 'enterers_location', 14 => 'call_back_phone_number', 15 => 'order_effective_datetime',
        16 => 'order_control_code_reason', 17 => 'entering_organization', 18 => 'entering_device',
        19 => 'action_by'
      },
      'OBR' => {
        1 => 'set_id', 2 => 'placer_order_number', 3 => 'filler_order_number', 4 => 'universal_service_identifier',
        5 => 'priority', 6 => 'requested_datetime', 7 => 'observation_datetime', 8 => 'observation_end_datetime',
        9 => 'collection_volume', 10 => 'collector_identifier', 11 => 'specimen_action_code', 12 => 'danger_code',
        13 => 'relevant_clinical_information', 14 => 'specimen_received_datetime', 15 => 'specimen_source',
        16 => 'ordering_provider', 17 => 'order_callback_phone_number', 18 => 'placer_field_1',
        19 => 'placer_field_2', 20 => 'filler_field_1', 21 => 'filler_field_2',
        22 => 'results_report_status_change_datetime', 23 => 'charge_to_practice',
        24 => 'diagnostic_service_section_id', 25 => 'result_status', 26 => 'parent_result',
        27 => 'quantity_timing', 28 => 'result_copies_to', 29 => 'parent', 30 => 'transportation_mode'
      },
      'OBX' => {
        1 => 'set_id', 2 => 'value_type', 3 => 'observation_identifier', 4 => 'observation_sub_id',
        5 => 'observation_value', 6 => 'units', 7 => 'references_range', 8 => 'abnormal_flags',
        9 => 'probability', 10 => 'nature_of_abnormal_test', 11 => 'observation_result_status',
        12 => 'effective_date_of_reference_range', 13 => 'user_defined_access_checks',
        14 => 'observation_datetime', 15 => 'producer_id', 16 => 'responsible_observer',
        17 => 'observation_method', 18 => 'equipment_instance_identifier', 19 => 'analysis_datetime'
      },
      'NTE' => {
        1 => 'set_id', 2 => 'source_of_comment', 3 => 'comment', 4 => 'comment_type'
      },
      'AL1' => {
        1 => 'set_id', 2 => 'allergen_type_code', 3 => 'allergen_code', 4 => 'allergy_severity_code',
        5 => 'allergy_reaction_code', 6 => 'identification_date'
      },
      'DG1' => {
        1 => 'set_id', 2 => 'diagnosis_coding_method', 3 => 'diagnosis_code', 4 => 'diagnosis_description',
        5 => 'diagnosis_datetime', 6 => 'diagnosis_type'
      }
    }.each_value(&:freeze).freeze

    POSITIONS = FIELD_NAMES.transform_values { |names| names.invert.freeze }.freeze

    module_function

    # Name used in the JSON document for field `position` of `segment`.
    def field_name(segment, position)
      FIELD_NAMES.dig(segment, position) || "field_#{position}"
    end

    # Position of a field given its JSON key: a known name, `field_<n>` or a bare number.
    def field_position(segment, key)
      key = key.to_s
      position = POSITIONS.dig(segment, key) || key[/\A(?:field_)?(\d+)\z/, 1]&.to_i
      return position if position&.positive?

      raise EncodeError, "Unknown field #{key.inspect} for segment #{segment} (use a known name or field_<position>)"
    end
  end
end
