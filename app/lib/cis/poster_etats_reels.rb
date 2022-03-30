# frozen_string_literal: true

module Cis
  class PosterEtatsReels < FieldChecker
    include Cis::Shared

    def must_check?(md_dossier)
      md_dossier&.state == 'accepte'
    end

    def version
      super + 1
    end

    def required_fields
      super + %i[champ_candidats_admis message nom_fichier]
    end

    def authorized_fields
      super + %i[mot_de_passe]
    end

    def process(_demarche, dossier)
      # return unless must_check?(dossier)

      champ = dossier_annotations(dossier, @params[:champ_candidats_admis])&.first
      return if champ&.file.nil?

      task_name = GenererModeleEtatReel.name.underscore
      start = start_date(champ)

      scheduled_dates = scheduled_dates(dossier, task_name)
      theoric_dates = remaining_dates(start)

      return if scheduled_dates == theoric_dates

      schedule_task(dossier, task_name, theoric_dates)
    end

    private

    def remaining_dates(start)
      start = start.at_beginning_of_month.next_month
      next_month = start.next_month
      [start, next_month, next_month.next_month].select { |date| date >= Date.today }
    end

    MONTHS = %w[Janvier Février Mars Avril Mai Juin Juillet Août Septembre Octobre Novembre Décembre].freeze

    def scheduled_dates(dossier, task_name)
      future = ScheduledTask.arel_table[:run_at].gteq(Date.today)
      ScheduledTask.where(dossier: dossier.number, task: task_name).where(future).pluck(:run_at)
    end

    def schedule_task(dossier, task_name, theoric_dates)
      dir = 'storage/etat_reel'
      FileUtils.mkpath(dir)
      flag = "#{dir}/#{dossier.number}.txt"
      return if File.exist?(flag)

      ScheduledTask.where(dossier: dossier.number, task: task_name).destroy_all

      theoric_dates.each.with_index do |date, index|
        date = date.prev_month
        parameters = {
          champ_candidats_admis: @params[:champ_candidats_admis],
          date: date,
          month: "#{MONTHS[date.month - 1]} #{date.year}",
          index: index+1,
          message: @params[:message],
          mot_de_passe: @params[:mot_de_passe],
          nom_fichier: @params[:nom_fichier]
        }
        ScheduledTask.create(dossier: dossier.number, task: task_name, parameters: parameters.to_json, run_at: date)
      end
      File.write(flag, theoric_dates.to_s)
    end

    def start_date(champ)
      PieceJustificativeCache.get(champ.file) do |file|
        table = Roo::Spreadsheet.open(file, { csv_options: { col_sep: ';' } })
        sheet = table.sheet(0)
        Date.strptime(sheet.cell(2, 2), '%d/%m/%Y')
      end
    end
  end
end
