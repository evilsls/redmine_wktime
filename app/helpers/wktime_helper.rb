module WktimeHelper 
  include Redmine::Export::PDF

	def options_for_period_select(value)
		options_for_select([[l(:label_all_time), 'all'],
							[l(:label_this_week), 'current_week'],
							[l(:label_last_week), 'last_week'],
							[l(:label_this_month), 'current_month'],
							[l(:label_last_month), 'last_month'],
							[l(:label_this_year), 'current_year']],
							value.blank? ? 'current_month' : value)
	end

	def options_wk_status_select(value)
		options_for_select([[l(:label_all), 'all'],
							[l(:wk_status_new), 'n'],
							[l(:wk_status_submitted), 's'],
							[l(:wk_status_approved), 'a'],
							[l(:wk_status_rejected), 'r']],
							value.blank? ? 'all' : value)
	end	
	
	def statusString(status)	
		statusStr = l(:wk_status_new)
		case status
		when 'a'
			statusStr = l(:wk_status_approved)
		when 'r'
			statusStr = l(:wk_status_rejected)
		when 's'
			statusStr = l(:wk_status_submitted)	
		else
			statusStr = l(:wk_status_new)
		end
		return statusStr
	end
	
	# Indentation of Subprojects based on levels
	def options_for_wktime_project(projects, needBlankRow=false)
		projArr = Array.new
		if needBlankRow
			projArr << [ "", ""]
		end
		
		#Project.project_tree(projects) do |proj_name, level|
		project_tree(projects) do |proj, level|
			indent_level = (level > 0 ? ('&nbsp;' * 2 * level + '&#187; ').html_safe : '')
			sel_project = projects.select{ |p| p.id == proj.id }
			projArr << [ (indent_level + sel_project[0].name), sel_project[0].id ]
		end
		projArr
	end

  # Returns a CSV string of a weekly timesheet
  def wktime_to_csv(entries, user, mon)
    decimal_separator = l(:general_csv_decimal_separator)
    custom_fields = WktimeCustomField.find(:all)
    export = FCSV.generate(:col_sep => l(:general_csv_separator)) do |csv|
      # csv header fields
      headers = [l(:field_user),
                 l(:field_project),
                 l(:field_issue),
                 l(:field_activity)
                 ]
		set_cf_header(headers, nil, 'wktime_enter_cf_in_row1')
		set_cf_header(headers, nil, 'wktime_enter_cf_in_row2')
		hoursIndex = headers.size

		for i in 0..6
			#Use "\n" instead of '\n'
			headers << (l('date.abbr_day_names')[(i+1)%7] + "\n" + I18n.localize(@mon+i, :format=>:short)) unless @mon.nil?
		end
      csv << headers.collect {|c| Redmine::CodesetUtil.from_utf8(
                  c.to_s, l(:general_csv_encoding) )  }
		weeklyHash = getWeeklyView(entries, true)
		col_values = []
		matrix_values = nil
		totals = [0.0,0.0,0.0,0.0,0.0,0.0,0.0]
		weeklyHash.each do |key, matrix|
			matrix_values, j = getColumnValues(matrix, totals)
			col_values = matrix_values[0]
			#add the user name to the values
			col_values.unshift(user.name)
			csv << col_values.collect {|c| Redmine::CodesetUtil.from_utf8(
								c.to_s, l(:general_csv_encoding) )  }
		end
		total_values = getTotalValues(totals, hoursIndex)
		#add an empty cell to cover for the user column
		#total_values.unshift("")
		csv << total_values.collect {|t| Redmine::CodesetUtil.from_utf8(
								t.to_s, l(:general_csv_encoding) )  }
    end
    export
  end
	

  # Returns a PDF string of a weekly timesheet
  def wktime_to_pdf(entries, user, mon)

	# Landscape A4 = 210 x 297 mm
	page_height   = Setting.plugin_redmine_wktime['wktime_page_height'].to_i
	page_width    = Setting.plugin_redmine_wktime['wktime_page_width'].to_i
	right_margin  = Setting.plugin_redmine_wktime['wktime_margin_right'].to_i
	left_margin  = Setting.plugin_redmine_wktime['wktime_margin_left'].to_i
	bottom_margin = Setting.plugin_redmine_wktime['wktime_margin_bottom'].to_i
	top_margin = Setting.plugin_redmine_wktime['wktime_margin_top'].to_i
	col_id_width  = 10
	row_height    = Setting.plugin_redmine_wktime['wktime_line_space'].to_i
	logo    = Setting.plugin_redmine_wktime['wktime_header_logo']

	if page_height == 0
		page_height = 297
	end
	if page_width == 0
		page_width  = 210
	end	
	if right_margin == 0
		right_margin = 10
	end	
	if left_margin == 0
		left_margin = 10
	end
	if bottom_margin == 0
		bottom_margin = 20
	end
	if top_margin == 0
		top_margin = 20
	end
	if row_height == 0
		row_height = 4
	end
	
	# column widths
	table_width = page_width - right_margin - left_margin
	
	columns = [l(:field_project), l(:field_issue), l(:field_activity)]

	col_width = []
	orientation = "P"
	
	# 20% for project, 60% for issue, 20% for activity
	col_width[0] = (table_width - (8*10))*0.2
	col_width[1] = (table_width - (8*10))*0.6
	col_width[2] = (table_width - (8*10))*0.2
	
	set_cf_header(columns, col_width, 'wktime_enter_cf_in_row1')
	set_cf_header(columns, col_width, 'wktime_enter_cf_in_row2')
	hoursIndex = columns.size
	for i in 0..6
		columns << l('date.abbr_day_names')[(i+1)%7] + "\n" + (mon+i).mon().to_s() + "/" + (mon+i).day().to_s()
		col_width << col_id_width
	end	
	
	#Landscape / Potrait
	if(table_width > 220)
		orientation = "L"
	else
		orientation = "P"
	end
	
	pdf = ITCPDF.new(current_language)
		
	pdf.SetTitle(l(:label_wktime))
	pdf.alias_nb_pages
	pdf.footer_date = format_date(Date.today)
	pdf.SetAutoPageBreak(false)
	pdf.AddPage(orientation)
	
	if !logo.blank?
		pdf.Image(Redmine::Plugin.public_directory + "/redmine_wktime/images/" + logo, page_width-10-20, 10)
	end
	
	render_header(pdf, entries, user, mon, row_height)

	pdf.Ln
	render_table_header(pdf, columns, col_width, row_height, col_id_width, table_width)

	weeklyHash = getWeeklyView(entries, true)
	col_values = []
	matrix_values = []
	totals = [0.0,0.0,0.0,0.0,0.0,0.0,0.0]
	grand_total = 0.0
	j = 0
	base_x = pdf.GetX
	base_y = pdf.GetY
	max_height = row_height
	  
	weeklyHash.each do |key, matrix|
		matrix_values, j = getColumnValues(matrix, totals, j)
		col_values = matrix_values[0]
		base_x = pdf.GetX
		base_y = pdf.GetY
		pdf.SetY(2 * page_height)
		#write once to get the height
		max_height = wktime_to_pdf_write_cells(pdf, col_values, col_width, row_height)
		#reset the x and y
		pdf.SetXY(base_x, base_y)

		# make new page if it doesn't fit on the current one
		space_left = page_height - base_y - bottom_margin
		if max_height > space_left
			pdf.AddPage(orientation)
			pdf.Image(Redmine::Plugin.public_directory + "/redmine_wktime/images/" + logo, page_width-10-20, 10)
			render_table_header(pdf, columns, col_width, row_height, col_id_width, table_width)
			base_x = pdf.GetX
			base_y = pdf.GetY
		end

		# write the cells on page
		pdf.RDMCell(col_id_width, row_height, j.to_s, "T", 0, 'C', 1)
		#on the second time, do the actual write
		wktime_to_pdf_write_cells(pdf, col_values, col_width, row_height)
		issues_to_pdf_draw_borders(pdf, base_x, base_y, base_y + max_height, col_id_width, col_width)

		pdf.SetY(base_y + max_height);
	end

	total_values = getTotalValues(totals,hoursIndex)
	
	#write total
	#write an empty id
	pdf.RDMCell(col_id_width, row_height, "", "T", 0, 'C', 1)

	max_height = wktime_to_pdf_write_cells(pdf, total_values, col_width, row_height)
	pdf.SetY(pdf.GetY);
	pdf.SetXY(pdf.GetX, pdf.GetY)
	render_signature(pdf, page_width, table_width, row_height)
	pdf.Output
  end
  
	# Renders MultiCells and returns the maximum height used
	def wktime_to_pdf_write_cells(pdf, col_values, col_widths,
								row_height)
		base_y = pdf.GetY
		max_height = row_height
		col_values.each_with_index do |val, i|
		  col_x = pdf.GetX
			pdf.RDMMultiCell(col_widths[i], row_height, val, "T", 'L', 1)
		  max_height = (pdf.GetY - base_y) if (pdf.GetY - base_y) > max_height
		  pdf.SetXY(col_x + col_widths[i], base_y);
		end
		return max_height
	end
	
	def getWeeklyView(entries, sumHours = false)
		weeklyHash = Hash.new
		prev_entry = nil
		entries.each do |entry|
			key = entry.project.id.to_s + (entry.issue.blank? ? '' : entry.issue.id.to_s) + entry.activity.id.to_s
			hourMatrix = weeklyHash[key]
			if hourMatrix.blank?
				#create a new matrix if not found
				hourMatrix =  []
				rows = []
				hourMatrix[0] = rows
				weeklyHash[key] = hourMatrix
			end
			
			#cwday returns 1 - 7, 1 is monday
			index = entry.spent_on.cwday - 1
			updated = false
			hourMatrix.each do |rows|
				if rows[index].blank?
					rows[index] = entry
					updated = true
					break
				else 
					if sumHours
						tempEntry = rows[index]
						tempEntry.hours += entry.hours
						updated = true
						break
					end
				end
			end
			if !updated
				rows = []
				hourMatrix[hourMatrix.size] = rows
				rows[index] = entry
			end

		end
		return weeklyHash
	end

def getColumnValues(matrix, totals, j=0)
	col_values = []
	matrix_values = []
	unless matrix.blank?
		matrix.each do |rows|
			issueWritten = false
			col_values = []
			matrix_values << col_values
			hoursIndex = 3
			rows.each.with_index do |entry, i|
				unless entry.blank?
					if !issueWritten
						col_values[0] = entry.project.name
						col_values[1] = entry.issue.blank? ? "" : entry.issue.subject
						col_values[2] = entry.activity.name
						custom_field_values = entry.custom_field_values
						set_cf_value(col_values, custom_field_values, 'wktime_enter_cf_in_row1')	
						set_cf_value(col_values, custom_field_values, 'wktime_enter_cf_in_row2')	
						hoursIndex = col_values.size
						issueWritten = true
						j += 1
					end
					col_values[hoursIndex+i] =  (entry.hours.blank? ? "" : entry.hours.to_s)
					totals[i] += entry.hours unless entry.hours.blank?
				end
			end
		end
	end	
	return matrix_values, j
end

def getTotalValues(totals, hoursIndex)
	grand_total = 0.0
	totals.each { |t| grand_total += t }
	#project, issue, is blank, and then total
	total_values = []
	for i in 0..hoursIndex-2
		total_values << ""
	end
	total_values << "#{l(:label_total)} = #{grand_total}"
	#concatenate two arrays
	total_values += totals.collect{ |t| t.to_s}
	return total_values
end

	
	def render_table_header(pdf, columns, col_width, row_height, col_id_width, table_width)
        # headers
        pdf.SetFontStyle('B',8)
        pdf.SetFillColor(230, 230, 230)

        # render it background to find the max height used
        base_x = pdf.GetX
        base_y = pdf.GetY
        max_height = wktime_to_pdf_write_cells(pdf, columns, col_width, row_height)
        #pdf.Rect(base_x, base_y, table_width + col_id_width, max_height, 'FD');
		pdf.Rect(base_x, base_y, table_width, max_height, 'FD');
        pdf.SetXY(base_x, base_y);

        # write the cells on page
        pdf.RDMCell(col_id_width, row_height, "#", "T", 0, 'C', 1)
        wktime_to_pdf_write_cells(pdf, columns, col_width, row_height)
        issues_to_pdf_draw_borders(pdf, base_x, base_y, base_y + max_height, col_id_width, col_width)
        pdf.SetY(base_y + max_height);

        # rows
        pdf.SetFontStyle('',8)
        pdf.SetFillColor(255, 255, 255)
    end

	def render_header(pdf, entries, user, mon, row_height)
		base_x = pdf.GetX
		base_y = pdf.GetY
		  
		# title
		pdf.SetFontStyle('B',11)
		pdf.RDMCell(100,10, l(:label_wktime))
		pdf.SetXY(base_x, pdf.GetY+row_height)
		
		render_header_elements(pdf, base_x, pdf.GetY+row_height, l(:field_name), user.name)
		#render_header_elements(pdf, base_x, pdf.GetY+row_height, l(:field_project), entries.blank? ? "" : entries[0].project.name)
		render_header_elements(pdf, base_x, pdf.GetY+row_height, l(:label_week), mon.to_s + " - " + (mon+6).to_s)
		render_customFields(pdf, base_x, user, mon, row_height)

	end
	
	def render_customFields(pdf, base_x, user, mon, row_height)
		if !@wktime.blank? && !@wktime.custom_field_values.blank?
			@wktime.custom_field_values.each do |custom_value|
				render_header_elements(pdf, base_x, pdf.GetY+row_height, 
					custom_value.custom_field.name, custom_value.value)
			end
		end
	end
	
	def render_header_elements(pdf, x, y, element, value="")

		pdf.SetXY(x, y)
		unless element.blank?
			pdf.SetFontStyle('B',8)
			pdf.RDMCell(50,10, element)
			pdf.SetXY(x+40, y)
			pdf.RDMCell(10,10, ":")
			pdf.SetFontStyle('',8)
			pdf.SetXY(x+40+2, y)
		end
		pdf.RDMCell(50,10, value)

	end
	
	def render_signature(pdf, page_width, table_width, row_height)
		base_x = pdf.GetX
		base_y = pdf.GetY
		
		submissionAck   = Setting.plugin_redmine_wktime['wktime_submission_ack']
		unless submissionAck.blank?
			pdf.SetY(base_y + row_height)
			pdf.SetXY(base_x, pdf.GetY+row_height)
			#to wrap text and to put it in multi line use MultiCell
			pdf.RDMMultiCell(table_width,5, submissionAck)
		end
		
		pdf.SetFontStyle('B',8)
		pdf.SetXY(page_width-90, pdf.GetY+row_height)
		pdf.RDMCell(50,10, l(:label_wk_signature) + " :")
		pdf.SetXY(page_width-90, pdf.GetY+(2*row_height))
		pdf.RDMCell(100,10, l(:label_wk_submitted_by) + " ________________________________")
		pdf.SetXY(page_width-90, pdf.GetY+ (2*row_height))
		pdf.RDMCell(100,10, l(:label_wk_approved_by) + " ________________________________")
	end
	
	def set_cf_header(columns, col_width, setting_name)
		cf_value = nil
		if !Setting.plugin_redmine_wktime[setting_name].blank? &&
			(cf_value = @new_custom_field_values.detect { |cfv| 
				cfv.custom_field.id == Setting.plugin_redmine_wktime[setting_name].to_i }) != nil
				
				columns << cf_value.custom_field.name
				unless col_width.blank?
					old_total = 0
					new_total = 0
					for i in 0..col_width.size-1
						old_total += col_width[i]
						if i == 1
							col_width[i] -= col_width[i]*10/100
						else
							col_width[i] -= col_width[i]*20/100
						end
						new_total += col_width[i]
					end
					# reset width 15% for project, 55% for issue, 15% for activity
					#col_width[0] *= 0.75
					#col_width[1] *= 0.9
					#col_width[2] *= 0.75
					
					col_width << old_total - new_total
				end
		end
	end

	def set_cf_value(col_values, custom_field_values, setting_name)	
		cf_value = nil
		if !Setting.plugin_redmine_wktime[setting_name].blank? &&
				(cf_value = custom_field_values.detect { |cfv| 
					cfv.custom_field.id == Setting.plugin_redmine_wktime[setting_name].to_i }) != nil
					col_values << cf_value.value
		end
	end
	
end