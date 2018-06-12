require 'rubygems'
require 'rubyXL'
require 'date'
require 'fileutils'
#require 'byebug'
require 'open-uri'
require 'csv'

class EpgController < ApplicationController
	DATE_COL = 0
  START_COL = 1
  TITLE_COL = 4
  FULL_HR_COL = 2
  SLOT_COL = 3
  SEASON_COL = 30
  EPISODE_COL =31
  REPEAT_COL = 24
  GENRE_ID_COL =7
  SUBGENRE_ID_COL = 9
  SUBGENRE_COL =11
  CERTIFICATION_COL = 12
  SYNOPSIS_COL = 16
  CC_COL = 29

	def index
		
	end

	def epg_generator
		@epg = params['epg']
    if params['submit'] == "Download meta missing file"
      download_meta_missing
    elsif params['submit'] == "Download validation errors file"
      download_validation_error
    elsif params['submit'] == "Download EPG"
      download_EPG(session[:passed_variable])
    else
      
      FileUtils.rm_rf(Dir["#{Rails.root}/public/output/*"])

  		meta_file = "public/#{@epg['meta'].original_filename}"
  		schedule_file = "public/#{@epg['schedule'].original_filename}"
  		template_file = "public/country_sky_template.xlsx"
  		output_dir = "#{Rails.root}/public/output"

  		FileUtils.cp("#{@epg['meta'].tempfile.path}","#{meta_file}")
  		FileUtils.cp("#{@epg['schedule'].tempfile.path}","#{schedule_file}")

  		month = Date::MONTHNAMES.index(File.basename(schedule_file,File.extname(schedule_file)).split("_").last.capitalize)
      session[:passed_variable] = "#{month}"
      if validate(meta_file,schedule_file,template_file,month,output_dir)
  		  parse(meta_file,schedule_file,template_file,month,output_dir)
  		  write_output()
  		end
  		write_error()

      metafile_size = (::ApplicationController.helpers.number_to_human_size(File.size("#{Rails.root}/public/output/meta_missing.csv"))).partition(" ").first.to_i
      puts metafile_size
      validation_errors_file_size = (::ApplicationController.helpers.number_to_human_size(File.size("#{Rails.root}/public/output/validation_errors.txt"))).partition(" ").first.to_i
      puts validation_errors_file_size

      if metafile_size > 20 or validation_errors_file_size > 0
        if validation_errors_file_size > 0
          @date_err = Array.new
          @title_err = Array.new
          @title = "Title not of format [<title>,<season> <ep_num>/<tot_ep> <(rpt) or (P)>]"
          @date = "Date not of format [DAY MMM DD YYYY]"
          @err = "validation_errors"
        else
          @rowarraydisp = CSV.read("#{Rails.root}/public/output/meta_missing.csv")
          @err = "metafile"
        end
        render 'epg/result'
      elsif metafile_size <= 20 and validation_errors_file_size == 0
        download_EPG(month)
      end 
    end
	end

  def download_meta_missing
    begin
      send_file "#{Rails.root}/public/output/meta_missing.csv", :disposition => 'attachment'
    rescue ex
      puts "error: #{ex.message}"
    end
  end

  def download_validation_error
    begin
      send_file "#{Rails.root}/public/output/validation_errors.txt", :disposition => 'attachment'
    rescue ex
      puts "error: #{ex.message}"
    end
  end

  def download_EPG(mon)
    begin
      send_file "#{Rails.root}/public/output/Country_SKY_EPG_#{mon}.xlsx", :disposition => 'attachment'
    rescue ex
      puts "error: #{ex.message}"
    end 
  end

	def get_formatted_time(time)
    return "24:00","00:00" if time.to_s == "1899-12-31T00:00:00+00:00"
    h,m = time.to_s.split(".")
    nh = ["0","1","2","3","4","5"].include?(h) ? (h.to_i + 24).to_s : h
    m = "0" unless m
    h = h.rjust(2, '0')
    nh = nh.rjust(2, '0')
    m = m.ljust(2, '0')
    return "#{nh}:#{m}","#{h}:#{m}"
  end

  def build_meta_data
    metadata = {}
    break_count = 0
    @metasheet.each_with_index do |row,index|
      next if index == 0
      break if break_count > 30
      if(row and row[0])
        break_count = 0
        metadata[row[0].value.to_s.strip() + "," + (!row[1].nil? ? row[1].value.to_s.gsub("s","").gsub("S","").strip() : "") + "," + (!row[2].nil? ? row[2].value.to_s.strip() : "")] = [
          row[3] ? row[3].value : "",
          row[4] ? row[4].value : "",
          row[4] ? row[4].value : "",
          row[5] ? row[5].value : "",
          row[7] ? row[7].value : "",
          ""
        ]
      else
        break_count += 1
      end
    end
    puts "#{metadata}"
    return metadata
  end

  def get_meta_data(title,ep,season)
    title = title.strip()
    ep = ep.strip()
    season = season.strip()
    ret  = @metadata[title+","+season.to_s+","+ep.to_s] || []
    if ret.empty?
      ret = @metadata[title+","+season+",Series"] || []
    end
    if ret.empty?
      ret = @metadata[title+",,"+"Single"] || []
    end
    @meta_missing << "#{title},#{season},#{ep}" if ret.empty?
    return ret
  end

  def get_genre_mapping(key_sheet,genre_id)
    other = nil
    (1..151).each do |row|
      if key_sheet[row][1].value =~ Regexp.new(genre_id) or Regexp.new(key_sheet[row][1].value) =~ genre_id
        genre_id = sprintf '%02d', key_sheet[row][0].value
        other = false
        break
      end
      if key_sheet[row][1].value == "Other" or key_sheet[row][1].value == "General"
        other = key_sheet[row][0].value
        break
      end
    end
    genre_id = other if other
    return genre_id
  end

  def get_subgenre_mapping(key_sheet,genre_id,sub_genre_id)
    other = nil
    (1..151).each do |row|
      if key_sheet[row][0].value.to_i == genre_id.to_i
        if key_sheet[row][4].value =~ Regexp.new(sub_genre_id) or Regexp.new(key_sheet[row][4].value) =~ sub_genre_id
          sub_genre_id = sprintf '%02d', key_sheet[row][3].value
          other = false
          break
        end
        if key_sheet[row][4].value == "Other" or key_sheet[row][4].value == "General"
          other = key_sheet[row][3].value
          break
        end
      end
    end
    sub_genre_id = other if other
    return sub_genre_id
  end

  def parse(meta_path,schedule_path,template_path,month,output)
    @output_dir = output
    puts "month: #{month}"
    @mnth = month
    metabook = RubyXL::Parser.parse(meta_path)
    @metasheet = metabook.worksheets[0]
    workbook = RubyXL::Parser.parse(schedule_path)
    @template_book = RubyXL::Parser.parse template_path
    template_sheet = @template_book.worksheets[1]
    key_sheet = @template_book.worksheets[2]
    cur_row_num = 1
    @meta_missing = ["Title,Season,Episode"]
    @metadata = build_meta_data()
    (0..5).each do |sheet_num|
      sheet = workbook.worksheets[sheet_num]
      (1..7).each do |num|
        stop_read = 0
        cur_date = ""
        skip_next_index = 0
        col_num = num
        ind = 0
        while true
          #sheet.column(num).each_with_index do |col_value,ind|
          col_value = (sheet.nil? or sheet[ind].nil? or sheet[ind][col_num].nil?) ? nil : sheet[ind][col_num].value
          cur_date = col_value if ind == 0
          break if cur_date.nil? or cur_date == " "
          cur_date = Date.strptime(cur_date.gsub(/\s\s+/," "),"%A, %d %B %Y").strftime("%d/%m/%Y") if ind == 0 and !cur_date.is_a?(DateTime)
          break if stop_read > 30
          if col_value.nil? or col_value =~ /^\s*$/ or ind < 2 or skip_next_index > 0 or (cur_date.is_a?(DateTime) and cur_date.mon != month.to_i) or (cur_date.is_a?(String) and Date.strptime(cur_date,"%d/%m/%Y").mon != month.to_i)
            stop_read += 1
            skip_next_index -= 1
            ind += 1
            next
          end
          begin
            stop_read = 0
            title,other = col_value.split(",")
            unless other
              ind += 1
              next
            end
            other = other.gsub(/\s\s+/," ")
            season,episode,repeat = other.split(" ")
            season,episode,repeat = "",season,episode if season and season.include?("/")
            current_episode,total_episode = episode.split("/")
            current_episode = current_episode.gsub("(","").gsub(")","")
            cur_time_val = sheet[ind][0].value if sheet[ind] and sheet[ind][0]
            next_cell_val = sheet[ind+1][num].value if sheet[ind+1] and sheet[ind+1][num]
            repeat_title_count = 0
            temp_ind = ind
            while true
              temp_ind += 1
              if sheet[temp_ind] and sheet[temp_ind][num] and sheet[temp_ind][num].value and sheet[temp_ind][num].value.gsub(/\s+/, " ") == col_value.gsub(/\s+/, " ")
                puts "#{col_value.gsub(/\s+/, " ")} : #{sheet[temp_ind][num].value.gsub(/\s+/, " ")}"
                repeat_title_count += 1
              else
                break
              end
            end
            full_time,time = get_formatted_time(cur_time_val)
            if repeat_title_count == 0
              hour_time = "00:30"
            elsif repeat_title_count == 1
              hour_time = "01:00"
            elsif repeat_title_count == 2
              hour_time = "01:30"
            elsif repeat_title_count == 3
              hour_time = "02:00"
            end
            skip_next_index = repeat_title_count
            genre_id,sub_genre_id,sub_genre,cert,synopsis,cc = get_meta_data(title,current_episode,season.gsub("s","").gsub("S",""))
            genre_id = self.get_genre_mapping(key_sheet,genre_id) if genre_id and genre_id.to_i == 0
            sub_genre_id = self.get_subgenre_mapping(key_sheet,genre_id,sub_genre_id) if sub_genre_id and sub_genre_id.to_i == 0
            template_sheet.add_cell(cur_row_num,DATE_COL,cur_date)
            template_sheet.add_cell(cur_row_num,START_COL,time.gsub("1899-12-31T15:30:00+00:00:00","15:30"))
            template_sheet.add_cell(cur_row_num,TITLE_COL,title)
            template_sheet.add_cell(cur_row_num,FULL_HR_COL,full_time.gsub("1899-12-31T15:30:00+00:00:00","15:30"))
            template_sheet.add_cell(cur_row_num,SLOT_COL,hour_time)
            template_sheet.add_cell(cur_row_num,SEASON_COL,season.gsub("s","").gsub("S",""))
            template_sheet.add_cell(cur_row_num,EPISODE_COL,current_episode)
            template_sheet.add_cell(cur_row_num,REPEAT_COL,(repeat == "(rpt)" ? 2 : 1))
            template_sheet.add_cell(cur_row_num,GENRE_ID_COL,genre_id)
            template_sheet.add_cell(cur_row_num,SUBGENRE_ID_COL,sub_genre_id)
            template_sheet.add_cell(cur_row_num,SUBGENRE_COL,sub_genre)
            template_sheet.add_cell(cur_row_num,CERTIFICATION_COL,(cert||"").gsub("16 Years +","16").gsub("PG - Content","PG"))
            template_sheet.add_cell(cur_row_num,SYNOPSIS_COL,synopsis)
            template_sheet.add_cell(cur_row_num,CC_COL,cc)
            cur_row_num += 1
            ind += 1
          rescue => ex
            col_value = (sheet.nil? or sheet[ind+1].nil? or sheet[ind+1][col_num].nil?) ? nil : sheet[ind+1][col_num].value
            if col_value.nil? or col_value == " "
              puts "No data in column #{col_num} of sheet #{sheet_num}"
              break
            end
            raise ex
            puts "#{ex.message}"
            puts "Title: #{title} sheet: #{sheet_num} column: #{num}"
            exit
          end
        end
      end
    end
  end

  def write_output
    @template_book.write File.join(@output_dir,"Country_SKY_EPG_#{@mnth}.xlsx")
    @errors = []
    self.write_error
  end

  def write_error
    File.open(File.join(@output_dir,"validation_errors.txt"),"w") do |file|
      file.write(@errors.join("\n"))
    end
    File.open(File.join(@output_dir,"meta_missing.csv"),"w") do |file|
      file.write(@meta_missing.join("\n"))
    end
    #self.move_files_to_out
  end

  def move_files_to_out
    FileUtils.mv(@schedule_path,@output_dir)
    FileUtils.mv(@metadata_path,@output_dir)
  end

  def validate(meta_path,schedule_path,template_path,month,output)
    @output_dir = output
    @errors = []
    @metadata_path = meta_path
    @meta_missing = ["Title,Season,Episode"]
    @schedule_path = schedule_path
    workbook = RubyXL::Parser.parse(schedule_path)
    @template_book = RubyXL::Parser.parse template_path
    (0..4).each do |sheet_num|
      sheet = workbook.worksheets[sheet_num]
      (1..7).each do |num|
        stop_read = 0
        cur_date = ""
        skip_next_index = false
        col_num = num
        ind = 0
        while true
          title = ""
          begin
            col_value = (sheet.nil? or sheet[ind].nil? or sheet[ind][col_num].nil?) ? nil : sheet[ind][col_num].value
            cur_date = col_value if ind == 0
            cur_date = Date.strptime(cur_date.gsub(/\s\s+/," "),"%A, %d %B %Y").strftime("%d/%m/%Y") if ind == 0 and cur_date and !cur_date.is_a?(DateTime)
            break if stop_read > 30
            if col_value.nil? or col_value =~ /^\s*$/ or ind < 2 or skip_next_index or (cur_date.is_a?(DateTime) and cur_date.mon != month.to_i) or (cur_date.is_a?(String) and Date.strptime(cur_date,"%d/%m/%Y").mon != month.to_i)
              if cur_date.nil? and ind == 0
                @errors << "Date not of format [DAY MMM DD YYYY] at sheet: #{sheet_num+1} column: #{num+1}"
                break
              end
              stop_read += 1
              skip_next_index = false
              ind += 1
              next
            end
            stop_read = 0
            title,other = col_value.split(",")
            other = other.gsub(/\s\s+/," ")
            season,episode,repeat = other.split(" ")
            season,episode,repeat = "",season,episode if season and season.include?("/")
            current_episode,total_episode = episode.split("/")
            current_episode = current_episode.gsub("(","").gsub(")","")
            cur_time_val = sheet[ind][0].value if sheet[ind] and sheet[ind][0]
            next_cell_val = sheet[ind+1][num].value if sheet[ind+1] and sheet[ind+1][num]
            full_time,time = get_formatted_time(cur_time_val)
            next_title = (next_cell_val || "").split(",")[0]
            if col_value and next_cell_val and col_value.strip() == next_cell_val.strip()
              hour_time = "01:00"
              skip_next_index = true
            else
              hour_time = "00:30"
              skip_next_index = false
            end
            ind += 1
          rescue => ex
            if ex.message.include?("undefined method `gsub'")
              @errors << "Title not of format [<title>,<season> <ep_num>/<tot_ep> <(rpt) or (P)>] at Title: #{title} sheet: #{sheet_num+1} column: #{num+1} Row: #{ind+1}"
            elsif ex.message.include?("invalid date")
                col_value = (sheet.nil? or sheet[ind+1].nil? or sheet[ind+1][col_num].nil?) ? nil : sheet[ind+1][col_num].value
                if col_value.nil? or col_value == " "
                  puts "No data in column #{col_num} of sheet #{sheet_num}"
                  break
                end
              @errors << "Date not of format [DAY MMM DD YYYY] at sheet: #{sheet_num+1} column: #{num+1}"
              break
            else
              @errors << "#{ex.message} at Title: #{title} sheet: #{sheet_num+1} column: #{num+1} Row: #{ind+1}"
            end
            ind += 1
          end
        end
      end
    end
    return true if @errors.size == 0
    return false
  end

end
