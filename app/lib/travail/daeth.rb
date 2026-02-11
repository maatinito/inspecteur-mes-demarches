# frozen_string_literal: true

module Travail
  class Daeth < FieldChecker
    ASSESSMENT_BASE = 'Assiette principale'
    DEFAULT_DUTY = "Obligation d'emploi par défaut"
    DISABLED_WORKER_FTE = 'ETP Bénéficiaires'
    DISMISSED_FTE = 'ETP Licenciés économiques'
    DUE_AMOUNT = 'Montant de la participation'
    ECAP_FTE = 'ETP ECAP'
    FINAL_DUTY = "Obligation d'emploi finale"
    FTE = 'ETP'
    OUTSOURCING = 'Sous-traitance'
    YEAR = 'Année'
    LATE_FEE = 'Montant de la pénalité'
    SURCHARGE = 'Montant de la majoration'
    TOTAL = 'Montant total'

    def version
      super + 1
    end

    def required_fields
      super + %i[champ_effectifs champ_effectif cellule_annee cellule_ETP cellule_ETP_ECAP cellule_assiette cellule_obligation cellule_licenciement champ_prestations champ_travailleurs
                 champs_par_travailleur]
    end

    def authorized_fields
      super + %i[smig]
    end

    def initialize(params)
      super
      champs = @params[:champs_par_travailleur]
      champs = champs&.split(',')&.map(&:strip) unless champs.is_a?(Array)
      if champs.blank? || champs.size < 10
        @errors << "10 champs doivent être déclarés dans 'champs_par_travailleur'"
        return
      end
      (@status, @contract_type, @contract_begin, @contract_end, @contract_hours, @cotorep_category, @cotorep_begin, @cotorep_end, @pdd_rate, @annuity) = champs

      @smig = @params[:smig].presence || 1024.74
      @duty_rate = (1000 * @smig).round
    end

    def in_excel(&block)
      champ = param_field(:champ_effectifs)
      begin
        champ_files = champ.files
      rescue GraphQL::Client::InvariantError
        champ_files = [champ.file]
      end
      if champ.blank? || champ.files.blank?
        @msgs << "Champ #{@params[:champ_effectifs]} vide."
        return block.call(nil)
      end
      file = champ_files.last
      if bad_extension?(File.extname(file.filename))
        @msgs << "Le fichier #{file.filename} n'est pas un fichier Excel"
        return block.call(nil)
      end
      read_file(file, &block)
    end

    def bad_extension?(extension)
      extension = extension&.downcase
      extension.nil? || !extension.end_with?('.xlsx')
    end

    def read_file(champ_file, &block)
      r = nil
      PieceJustificativeCache.get(champ_file) do |file|
        excel = Roo::Spreadsheet.open(file)
        sheet = excel.sheet(0)
        r = block.call(sheet) if block_given?
      rescue RangeError
        @msgs << "Impossible de lire les valeurs en D8 et D9 dans le fichier #{file.filename}"
        r = block.call(nil) if block_given?
      ensure
        excel&.close
      end
      r
    end

    def save_messages(messages)
      save_annotation('Messages du robot', messages)
      messages
    end

    STATUS_COTOREP = 'Reconnu COTOREP'
    STATUS_PDD = "Victime d'accident du travail ou maladie professionnelle" # Permanent Partial Disability
    STATUS_PENSION = 'Pensionné invalide'

    CONTRACT_SITH = 'Stagiaire SITH'
    CONTRACT_CDI = 'CDI'
    CONTRACT_FPT = 'FPT'
    CONTRACT_FPT_STAGIAIRE = 'FPT stagiaire'
    CONTRACT_ANFA = 'ANFA'
    CONTRACT_ANT = 'ANT'

    # Types de contrats qui suivent la règle "annualisée" :
    # Si présent avant 1/10 ET au 31/12 => compté toute l'année
    ANNUALIZED_CONTRACTS = [CONTRACT_CDI, CONTRACT_FPT, CONTRACT_FPT_STAGIAIRE, CONTRACT_ANFA].freeze

    YEAR_START_MONTH = 1
    YEAR_START_DAY = 1
    OCTOBER_MONTH = 10
    OCTOBER_DAY = 1

    def disabled_workers
      year = declaration_year
      dates = initialize_year_dates(year)
      rows = param_field(:champ_travailleurs, warn_if_empty: false)&.rows || []
      rows.map do |row|
        fields = row.champs.each_with_object({}) { |c, h| h[c.label] = c.respond_to?(:value) ? c.value : c }
        disabled_worker_attributes(fields).merge!(disabled_worker_complement(fields, dates))
      end
    end

    def disabled_worker_fte
      dw = disabled_workers
      return 0.0 if dw.blank?

      worker_rates = dw.map do |worker|
        if worker[:contract_type] == CONTRACT_SITH
          @msgs << "Travailleur #{worker[:contract_type]} ignoré"
          next 0
        end

        year_presence_rate = compute_year_presence_rate(worker)
        weekly_presence_rate = compute_weekly_presence_rate(worker)
        payload, msg = payload(worker)
        @msgs << "#{payload} = #{msg}, h/sem: #{(weekly_presence_rate * 100).round(1)}%  présence annuelle:#{(year_presence_rate * 100).round(1)}%"
        (payload * weekly_presence_rate * year_presence_rate).round(3)
      end
      worker_rates.sum.round(3)
    end

    def levy(duty)
      (duty * @duty_rate).round
    end

    def process(demarche, dossier)
      super
      return unless dossier_has_right_state?

      @msgs = []
      @numbers = default_numbers
      # return unless @numbers[DEFAULT_DUTY] >= 0

      @numbers[DISABLED_WORKER_FTE] = disabled_worker_fte
      @numbers[FINAL_DUTY] = duty = final_duty
      @numbers[DUE_AMOUNT] = levy(duty)
      @numbers[LATE_FEE] = (@smig * 200).round unless @numbers[LATE_FEE].positive? || dossier.date_depot < Time.zone.local(Date.today.year, 4, 1)
      @numbers[TOTAL] = @numbers[LATE_FEE] + @numbers[SURCHARGE] + @numbers[DUE_AMOUNT]

      save_results(@numbers)
      save_messages(@msgs.join("\n"))
    end

    private

    def final_duty
      duty = (@numbers[DEFAULT_DUTY] - @numbers[OUTSOURCING] - @numbers[DISMISSED_FTE] - @numbers[DISABLED_WORKER_FTE]).round(3)
      duty = 0.0 if duty.negative?
      duty.round(3)
    end

    def default_numbers
      base = {
        LATE_FEE => annotation(LATE_FEE, warn_if_empty: false)&.value.to_i,
        SURCHARGE => annotation(SURCHARGE, warn_if_empty: false)&.value.to_i,
        OUTSOURCING => param_field(:champ_prestations, warn_if_empty: false)&.value.presence.to_f
      }
      effectif = param_field(:champ_effectif, warn_if_empty: false)
      base.merge!(effectif.present? ? default_numbers_based_on_size(effectif) : default_numbers_based_on_excel)
      @year = base[YEAR]
      base
    end

    def default_numbers_based_on_excel
      in_excel do |sheet|
        {
          YEAR => cell(sheet, @params[:cellule_annee], Date.today.year - 1),
          FTE => cell(sheet, @params[:cellule_ETP], 0.0).to_f.round(3),
          ECAP_FTE => cell(sheet, @params[:cellule_ETP_ECAP], 0.0).to_f.round(3),
          ASSESSMENT_BASE => cell(sheet, @params[:cellule_assiette], 0.0).to_f.round(3),
          DEFAULT_DUTY => cell(sheet, @params[:cellule_obligation], 0.0).to_f.round(3),
          DISMISSED_FTE => cell(sheet, @params[:cellule_licenciement], 0.0).to_f.round(3)
        }
      end
    end

    def default_numbers_based_on_size(effectif)
      effectif = effectif&.value&.to_f
      {
        YEAR => year_from_date_depot,
        FTE => effectif,
        ECAP_FTE => 0.0,
        ASSESSMENT_BASE => effectif,
        DEFAULT_DUTY => effectif < 25 ? 0.0 : (effectif * 0.02 / 0.5).floor * 0.5,
        DISMISSED_FTE => 0.0
      }
    end

    # Calcule l'année de déclaration à partir de la date de dépôt du dossier
    # Si date_depot > 1er juin => année en cours, sinon année précédente
    def year_from_date_depot
      date_depot = DateTime.parse(@dossier.date_depot)
      june_first = Date.new(date_depot.year, 6, 1)
      date_depot >= june_first ? date_depot.year : date_depot.year - 1
    end

    def disabled_worker_attributes(fields)
      {
        status: fields[@status],
        contract_type: fields[@contract_type],
        contract_begin: fields[@contract_begin].present? ? Date.parse(fields[@contract_begin]) : nil,
        contract_end: fields[@contract_end].present? ? Date.parse(fields[@contract_end]) : nil,
        contract_hours: fields[@contract_hours]&.to_i
      }
    end

    def disabled_worker_complement(fields, dates)
      case fields[@status]
      when STATUS_COTOREP
        {
          cotorep_category: fields[@cotorep_category],
          cotorep_begin: fields[@cotorep_begin].present? ? Date.parse(fields[@cotorep_begin]) : dates[:year_start],
          cotorep_end: fields[@cotorep_end].present? ? Date.parse(fields[@cotorep_end]) : dates[:year_end]
        }
      when STATUS_PDD
        {
          pdd_rate: fields[@pdd_rate].to_i,
          annuity: fields[@annuity]
        }
      else
        {}
      end
    end

    def cell(sheet, var, default)
      return default unless sheet

      column, line = var.match(/^([A-Z]+)(\d+)$/).captures
      sheet.cell(line.to_i, column)
    end

    def compute_weekly_presence_rate(worker)
      return 1 unless worker[:contract_hours].present?

      weekly_presence_rate = worker[:contract_hours] / 39.0
      weekly_presence_rate = 1 if weekly_presence_rate >= 0.5
      weekly_presence_rate
    end

    def compute_year_presence_rate(worker)
      year = declaration_year
      dates = initialize_year_dates(year)

      contract_dates = calculate_contract_dates(worker, dates)
      apply_annualized_contract_rules(worker, contract_dates, dates, year) if ANNUALIZED_CONTRACTS.include?(worker[:contract_type])
      apply_cotorep_rules(worker, contract_dates)

      calculate_presence_rate(contract_dates[:end_date], contract_dates[:begin_date], dates[:year_days])
    end

    def initialize_year_dates(year)
      year_start = Date.new(year, YEAR_START_MONTH, YEAR_START_DAY)
      year_end = Date.new(year + 1, YEAR_START_MONTH, YEAR_START_DAY)
      {
        year_start:,
        year_end:,
        year_days: (year_end - year_start).to_f
      }
    end

    def calculate_contract_dates(worker, dates)
      year_range = dates[:year_start]...dates[:year_end]
      contract_begin = worker[:contract_begin] || dates[:year_start]
      contract_end = normalize_end_date(worker[:contract_end], dates[:year_end])
      contract_range = contract_begin...contract_end
      i = intersection(year_range, contract_range)
      {
        begin_date: i.begin,
        end_date: i.end
      }
    end

    def normalize_end_date(end_date, year_end)
      return year_end if end_date.blank? || end_date > year_end

      end_date + 1
    end

    def intersection(range_a, range_b)
      return range_a.begin...range_a.begin if range_a.end < range_b.begin || range_b.end < range_a.begin

      [range_a.begin, range_b.begin].max...[range_a.end, range_b.end].min
    end

    def normalize_begin_date(begin_date, year_start)
      return year_start if begin_date.blank? || begin_date < year_start

      begin_date
    end

    # Applique la règle "annualisée" pour les contrats CDI, FPT, FPT Stagiaire et ANFA :
    # Si le travailleur est présent avant le 1er octobre ET au 31 décembre,
    # il est compté comme présent toute l'année
    def apply_annualized_contract_rules(_worker, contract_dates, dates, year)
      october_first = Date.new(year, OCTOBER_MONTH, OCTOBER_DAY)
      return unless contract_dates[:begin_date] <= october_first && contract_dates[:end_date] >= dates[:year_end]

      contract_dates[:begin_date] = dates[:year_start]
    end

    def apply_cotorep_rules(worker, contract_dates)
      contract_dates[:end_date] = [contract_dates[:begin_date], worker[:cotorep_end]].max if worker[:cotorep_end].present? && worker[:cotorep_end] < contract_dates[:end_date]

      return unless worker[:cotorep_begin].present? && worker[:cotorep_begin] > contract_dates[:begin_date]

      contract_dates[:begin_date] = [contract_dates[:end_date], worker[:cotorep_begin]].min
    end

    def calculate_presence_rate(end_date, begin_date, year_days)
      presence_days = (end_date - begin_date).to_f
      presence_days / year_days
    end

    def payload(worker)
      case worker[:status]
      when STATUS_PENSION
        payload = 1
        msg = STATUS_PENSION
      when STATUS_PDD
        payload = worker[:annuity] && worker[:pdd_rate] > 20 ? 1 : 0
        msg = "#{worker[:status]}: #{worker[:annuity] ? 'avec' : 'sans'} pension, #{worker[:pdd_rate]}% d'invalidité"
      when STATUS_COTOREP
        payload = worker[:cotorep_category] == 'C' ? 2 : 1
        cotorep_begin = worker[:cotorep_begin]
        cotorep_end = worker[:cotorep_end]
        # payload = 0 if cotorep_begin.blank? || cotorep_end.blank?
        msg = "#{worker[:status]}: #{worker[:cotorep_category]}, valide entre #{cotorep_begin} et #{cotorep_end}"
      else
        payload = 0
        msg = "Statut du travailleur handicapé inconnu '#{worker[:status]}'"
      end
      [payload, msg]
    end

    def declaration_year
      @year || (Date.today.year - 1)
    end

    def save_results(numbers)
      numbers.each do |key, value|
        value = value.zero? ? '' : value.to_s if value.is_a?(Float)
        save_annotation(key, value)
      end
    end

    def save_annotation(field, value)
      changed = SetAnnotationValue.set_value(@dossier, @demarche&.instructeur || instructeur_id, field, value)
      dossier_updated(@dossier) if changed
      value
    end

    def dossier_has_right_state?
      @states.include?(@dossier.state)
    end
  end
end
