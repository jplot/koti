# frozen_string_literal: true

module Miele
  module Sdk
    class TumbleDryer < Appliance
      # The parameters the app writes on a tumble dryer: 2/1577's +selection_para_td+ on DOP2, 8602's write section
      # on Dop1 ({Laundry::Parameters}).
      module Parameters
        DOP2_EXTRAS = %i[eco gentle short refresh hygiene single_dry anti_crease gentle_simple dry_care40 dry_fresh
                         power_fresh].freeze
        DOP1_EXTRAS = { refresh: :extra_auffrischen, eco: :extra_eco, hygiene: :extra_hygiene,
                        anti_crease: :extra_knitterschutz, short: :extra_kurz, single_dry: :extra_mengenautomatik,
                        gentle: :extra_schonen }.freeze
        COPIED = { delayed_start: %i[delayed_start current_value],
                   delayed_start_mode: %i[delayed_start_mode current_value],
                   residual_moisture: %i[residual_moisture current_value],
                   drying_time: %i[drying_time current_value] }.freeze
        COPIED_EXTRAS = { eco: %i[eco current_value], gentle: %i[gentle current_value] }.freeze
        DOP1_COPIED = %i[programm_id typ favoriten_nr multiartikel restfeuchte_stufe trockenzeit extra_schonen
                         extra_kurz extra_hygiene extra_auffrischen extra_mengenautomatik extra_eco
                         extra_knitterschutz].freeze
        # The app writes 255 for any other level.
        DOP1_LEVELS = { machine_iron: 6, hand_iron_plus: 5, hand_iron: 4, slightly_dry: 3, cupboard_dry: 2,
                        cupboard_dry_plus: 1, extra_dry: 0 }.freeze
        SMART_BIZ_LEVELS = { deficiency_dry: 1, iron_dry: 4 }.freeze
        private_constant :DOP2_EXTRAS, :DOP1_EXTRAS, :COPIED, :COPIED_EXTRAS, :DOP1_COPIED, :DOP1_LEVELS,
                         :SMART_BIZ_LEVELS

        private

        # @return [Symbol]
        def para_member = :selection_para_td

        # @return [Array<Symbol>]
        def parameter_names = %i[extras drying_level drying_time]

        # @return [Hash{Symbol=>Array<Symbol>}]
        def setting_choices
          { extras: dop2? ? DOP2_EXTRAS : DOP1_EXTRAS.keys, drying_level: Laundry::DRYING_LEVELS.keys }
        end

        # @param para [Objects::Laundry::GlobalPsSelectionParaTD]
        # @param source [Objects::Laundry::GlobalPsContextParaTD]
        # @return [Objects::Laundry::GlobalPsSelectionParaTD]
        def appliance_values(para, source)
          para = copied(para, source, COPIED)
          para.extras && source.extras ? para.with(extras: copied(para.extras, source.extras, COPIED_EXTRAS)) : para
        end

        # @param para [Objects::Laundry::GlobalPsSelectionParaTD]
        # @param settings [Hash{Symbol=>Object}]
        # @return [Objects::Laundry::GlobalPsSelectionParaTD]
        def dop2_parameters(para, settings)
          para = para.with(extras: chosen(para.extras, settings[:extras], DOP2_EXTRAS)) if settings.key?(:extras)
          para = para.with(drying_time: settings[:drying_time]) if settings.key?(:drying_time)
          return para unless settings.key?(:drying_level)

          para.with(residual_moisture: residual_moisture(settings[:drying_level]))
        end

        # A SmartBiz dryer (+TechType+ PDR…) takes deficiency and iron dry as 1 and 4.
        #
        # @param level [Symbol] a key of {Laundry::DRYING_LEVELS}
        # @return [Integer]
        def residual_moisture(level)
          smart_biz = SMART_BIZ_LEVELS[level] if identity.device_type == 2 && tech_type.to_s.include?('PDR')
          smart_biz || Laundry::DRYING_LEVELS.fetch(level)
        end

        # @param current [Objects::Laundry::TdProgrammwahlSetzen] 8602 as read
        # @param settings [Hash{Symbol=>Object}]
        # @return [Data] 8602's write section
        def dop1_parameters(current, settings)
          status = current.status
          blank(Objects::Laundry::TdProgrammwahlSetzen::SettingWriteSection)
            .with(struktur_version: status.version_der_struktur, **status.to_h.slice(*DOP1_COPIED),
                  **dop1_values(settings))
        end

        # @param settings [Hash{Symbol=>Object}]
        # @return [Hash{Symbol=>Integer}]
        def dop1_values(settings)
          extras = settings[:extras]
          values = DOP1_EXTRAS.filter_map { |name, bit| [bit, extras.include?(name) ? 1 : 0] if extras }.to_h
          values[:trockenzeit] = settings[:drying_time] if settings.key?(:drying_time)
          values[:restfeuchte_stufe] = DOP1_LEVELS.fetch(settings[:drying_level], 255) if settings.key?(:drying_level)
          values
        end
      end
    end
  end
end
