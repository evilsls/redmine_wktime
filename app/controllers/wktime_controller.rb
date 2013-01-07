class WktimeController < ApplicationController
unloadable

include WktimeHelper

before_filter :require_login
before_filter :check_perm_and_redirect, :only => [:edit, :update]
before_filter :check_editperm_redirect, :only => [:destroy]
helper :custom_fields


  def index
    retrieve_date_range	
	@from = getMonday(@from)
	@to = getSunday(@to)
	
    respond_to do |format|
      format.html {
        # Paginate results
		user_id = params[:user_id]
		set_user_projects
		ids = nil		
		if user_id.blank?
			ids = User.current.id.to_s
		elsif user_id.to_i == 0
			#all users
			@selected_project.members.each_with_index do|m, i|
				if i == 0
					ids =  m.user_id.to_s
				else
					ids +=  ',' + m.user_id.to_s
				end
			end		
			ids = User.current.id.to_s if ids.nil?
		else
			ids = user_id
		end
		selectStr = "select v1.user_id, v1.monday as spent_on, v1.hours "
		wkSelectStr = selectStr + ", w.status "
		sqlStr = " from "
		
		# postgre doesn't have the weekday function
		# The day of the week (0 - 6; Sunday is 0)
		if ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
			sqlStr += " (select case when cast(extract(dow from t.spent_on) as integer) = 0 then t.spent_on - 6" +
				" else t.spent_on - (cast(extract(dow from t.spent_on) as integer) - 1) end as monday, "
		elsif ActiveRecord::Base.connection.adapter_name == 'SQLite'
			sqlStr += " (select date(spent_on, '-' || strftime('%w', spent_on, '-1 days') || ' days') as monday, "
		else
			# mysql - the weekday index for date (0 = Monday, 1 = Tuesday, … 6 = Sunday)
			sqlStr += " (select adddate(t.spent_on,weekday(t.spent_on)*-1) as monday, "
		end
		sqlStr += " t.user_id, sum(t.hours) as hours from time_entries t, users u" +
			" where u.id = t.user_id and u.id in (#{ids})"
		sqlStr += " and t.spent_on between '#{@from}' and '#{@to}'" unless @from.blank? && @to.blank?
		sqlStr += " group by monday, user_id order by monday desc, user_id) as v1"	
		
		wkSqlStr = " left outer join wktimes w on v1.monday = w.begin_date and v1.user_id = w.user_id"	
		status = params[:status]
		if !status.blank? && status != 'all'
			wkSqlStr += " WHERE w.status = '#{status}'" 
			if status == 'n'
				wkSqlStr += " OR  w.status IS NULL"
			end
		end
		 
		result = TimeEntry.find_by_sql("select count(*) as id from (" + selectStr + sqlStr + ") as v2")
		@entry_count = result[0].id
        @entry_pages = Paginator.new self, @entry_count, per_page_option, params['page']
			
		@entries = TimeEntry.find_by_sql(wkSelectStr + sqlStr + wkSqlStr +
			" LIMIT " + @entry_pages.items_per_page.to_s +
			" OFFSET " + @entry_pages.current.offset.to_s)
			
        #@total_hours = TimeEntry.visible.sum(:hours, :include => [:user], :conditions => cond.conditions).to_f
		result = TimeEntry.find_by_sql("select sum(v2.hours) as hours from (" + selectStr + sqlStr + ") as v2")
		@total_hours = result[0].hours
        render :layout => !request.xhr?
      }
    end

  end

  def edit
	respond_to do |format|
		format.html {
			@prev_template = false
			@new_custom_field_values = TimeEntry.new.custom_field_values
			setup
			findWktime(@mon)
			@editable = @wktime.nil? || @wktime.status == 'n' || @wktime.status == 'r'
			@entries = findEntries()
			set_project_issues(@entries)
			if @entries.blank? && !params[:prev_template].blank?
				@prev_entries = prevTemplate(@user.id)
				if !@prev_entries.blank?
					set_project_issues(@prev_entries)
					@prev_template = true
				end
			end
			render :layout => !request.xhr?
		} 
		format.api  {
		}
	end
  end

  # called when save is clicked on the page
  def update
  	respond_to do |format|
		format.html {
			total = params[:total].to_f
			gatherEntries
			set_loggable_projects
			@wktime = nil
			findWktime(@mon)
			@wktime = Wktime.new if @wktime.nil?
			gatherWkCustomFields(@wktime)
			errorMsg = nil
			TimeEntry.transaction do
				begin				
					if !params[:wktime_save].blank? ||
						!params[:wktime_submit].blank?
						@wktime.status = :n
						# save each entry
						@entries.each do |entry|
							errorMsg = updateEntry(entry)
							break unless errorMsg.blank?
						end
						if !params[:wktime_submit].blank?
							@wktime.submitted_on = Date.today
							@wktime.submitter_id = User.current.id
							@wktime.status = :s
							if !Setting.plugin_redmine_wktime['wktime_uuto_approve'].blank? &&
								Setting.plugin_redmine_wktime['wktime_uuto_approve'].to_i == 1
								@wktime.status = :a
							end
						end
						
						@wktime.hours = total
						errorMsg = 	updateWktime if (errorMsg.blank? && total > 0.0)
					end

					if errorMsg.blank?
						if !params[:wktime_approve].blank?
							errorMsg = updateStatus(:a)
						elsif !params[:wktime_reject].blank? || !params[:hidden_wk_reject].blank?
							@wktime.notes = params[:wktime_notes] unless params[:wktime_notes].blank?
							errorMsg = updateStatus(:r)
						elsif !params[:wktime_unsubmit].blank?
							errorMsg = updateStatus(:n)
						elsif !params[:wktime_unapprove].blank?
							errorMsg = updateStatus(:s)
						end
					end
				rescue Exception => e			
					errorMsg = e.message
				end
				
				if errorMsg.nil?
					#when the are entries or it is not a save action
					if !@entries.blank? || !params[:wktime_approve].blank? || 
						(!params[:wktime_reject].blank? || !params[:hidden_wk_reject].blank?) ||
						!params[:wktime_unsubmit].blank? || !params[:wktime_unapprove].blank? ||
						(!params[:wktime_submit].blank? && total > 0.0)
						flash[:notice] = l(:notice_successful_update)
					else
						flash[:notice] = l(:error_wktime_save_nothing)
					end
					#redirect_back_or_default :action => 'index'
					redirect_to :action => 'index'
				else					
					flash[:error] = l(:error_wktime_save_failed, errorMsg)	
					if !params[:enter_issue_id].blank? && params[:enter_issue_id].to_i == 1					
						redirect_to :action => 'edit', :user_id => params[:user_id], :mon => @mon,
						:enter_issue_id => 1	
					else
						redirect_to :action => 'edit', :user_id => params[:user_id], :mon => @mon
					end
					raise ActiveRecord::Rollback
				end
			end
		} 
		format.api  {
		}
	end  
  end
	
	def deleterow
		if check_editPermission
			ids = params['ids']
			TimeEntry.delete(ids)	
			respond_to do |format|
				format.text  { 
					render :text => 'OK' 
				}
			end
		else
			respond_to do |format|
				format.text  { 
					render :text => 'FAILED' 
				}
			end
		end
	end

	def destroy	
		respond_to do |format|
			format.html {
				setup
				#cond = getCondition('spent_on', @user.id, @mon, @mon+6)
				#TimeEntry.delete_all(cond)
				@entries = findEntries()
				@entries.each do |entry|
					entry.destroy()
				end
				cond = getCondition('begin_date', @user.id, @mon)
				Wktime.delete_all(cond)
				flash[:notice] = l(:notice_successful_delete)
				redirect_back_or_default :action => 'index'
			} 
			format.api  {
			}
		end
	end
	
	def new
		set_user_projects
		# get the monday for current week
		@mon = getMonday(Date.today)
		render :action => 'new'
	end
	
	
	
  def getissues
	if Setting.plugin_redmine_wktime['wktime_closed_issue_ind'].to_i == 1
		issues = Issue.find_all_by_project_id(params[:project_id] || params[:project_ids], :order => 'project_id')
	else
		issues = Issue.find_all_by_project_id(params[:project_id] || params[:project_ids],
		:conditions => ["#{IssueStatus.table_name}.is_closed = ? OR #{Issue.table_name}.updated_on >= ?", false, @mon],
		:include => :status, :order => 'project_id')
	end
	
	user = User.find(params[:user_id])
	
	issStr =""
	issues.each do |issue|
		issStr << issue.project_id.to_s() + '|' + issue.id.to_s() + '|' + issue.tracker.to_s() +  '|' + 
				issue.subject  + "\n" if issue.visible?(user)
	end
	respond_to do |format|
		format.text  { render :text => issStr }
	end
  end
  
	def getactivities
		project = nil
		error = nil
		project_id = params[:project_id]
		if !project_id.blank?
			project = Project.find(project_id)
		elsif !params[:issue_id].blank?
			issue = Issue.find(params[:issue_id])
			project = issue.project
			project_id = project.id
			u_id = params[:user_id]
			user = User.find(u_id)
			if !user_allowed_to?(:log_time, project)
				error = "403"
			end
		else
			error = "403"
		end
		actStr =""
		project.activities.each do |a|
			actStr << project_id.to_s() + '|' + a.id.to_s() + '|' + a.name + "\n"
		end
	
		respond_to do |format|
			format.text  { 
			if error.blank?
				render :text => actStr 
			else
				render_403
			end
			}
		end
	end
	
	def getusers
		project = Project.find(params[:project_id])
		userStr =""
		project.members.each do |m|
			userStr << m.user_id.to_s() + ',' + m.name + "\n"
		end
	
		respond_to do |format|
			format.text  { render :text => userStr }
		end
	end

  # Export wktime to a single pdf file
  def export
    respond_to do |format|
		@new_custom_field_values = TimeEntry.new.custom_field_values
		@entries = findEntries()
		findWktime(@mon)
		format.pdf {
			send_data(wktime_to_pdf(@entries, @user, @mon), :type => 'application/pdf', :filename => "#{@mon}-#{params[:user_id]}.pdf")
		}
		format.csv {
			send_data(wktime_to_csv(@entries, @user, @mon), :type => 'text/csv', :filename => "#{@mon}-#{params[:user_id]}.csv")
      }
    end
  end
	
private

	def getCondition(date_field, user_id, start_date, end_date=nil)
		cond = nil
		if end_date.nil?
			cond = user_id.nil? ? [ date_field + ' = ?', start_date] :
				[ date_field + ' = ? AND user_id = ?', start_date, user_id]
		else
			cond = user_id.nil? ? [ date_field + ' BETWEEN ? AND ?', start_date, end_date] :
			[ date_field + ' BETWEEN ? AND ? AND user_id = ?', start_date, end_date, user_id]
		end
		return cond
	end
	
	#change the date to a monday
	def getMonday(date)
		unless date.nil?
			#the day of calendar week (1-7, Monday is 1)
			day1_diff = date.cwday%7 - 1
			#date -= day1_diff if day1_diff != 0
			date -= day1_diff == -1 ? 6 : day1_diff
		end
		date
	end

	#change the date to a sunday
	def getSunday(date)
		unless date.nil?
			day7_diff = 7 - date.cwday%7
			date += day7_diff == 7 ? 0 : day7_diff
		end
		date
	end
	
	def prevTemplate(user_id)
		# the weekday index for date (0 = Monday, 1 = Tuesday, … 6 = Sunday)
		sqlStr = "select max(spent_on) as max_spent_on from time_entries" +
			" where user_id = " + user_id.to_s
		result = TimeEntry.find_by_sql(sqlStr)
		prev_entries = nil
		max_spent_on = result[0].max_spent_on
		unless max_spent_on.blank?
			start = getMonday(max_spent_on.to_date)
			cond = getCondition('spent_on', user_id, start, start+6)
			prev_entries = TimeEntry.find(:all, :conditions => cond,
					:order => 'project_id, issue_id, activity_id, spent_on')
		end
		prev_entries

	end

	
  def gatherEntries
		entryHash = params[:time_entry]
		@entries ||= Array.new
		custom_values = Hash.new
		setup
		decimal_separator = l(:general_csv_decimal_separator)
		use_detail_popup = !Setting.plugin_redmine_wktime['wktime_use_detail_popup'].blank? &&
			Setting.plugin_redmine_wktime['wktime_use_detail_popup'].to_i == 1
		custom_fields = TimeEntryCustomField.find(:all)
							
		unless entryHash.nil?
			entryHash.each_with_index do |entry, i|
				if !entry['project_id'].blank?
					hours = params['hours' + (i+1).to_s()]					
					ids = params['ids' + (i+1).to_s()]
					comments = params['comments' + (i+1).to_s()]
					disabled = params['disabled' + (i+1).to_s()]
					
					if use_detail_popup
						custom_values.clear
						custom_fields.each do |cf|
							custom_values[cf.id] = params["_custom_field_values_#{cf.id}" + (i+1).to_s()]
						end
					end
					
					j = 0
					ids.each_with_index do |id, k|
						if disabled[k] == "false"
							if(!id.blank? || !hours[j].blank?)
								timeEntry = nil

								timeEntry = id.blank? ? TimeEntry.new : TimeEntry.find(id)								
								timeEntry.attributes = entry
								# since project_id and user_id is protected
								timeEntry.project_id = entry['project_id']
								timeEntry.user_id = @user.id
								timeEntry.spent_on = @mon + k
								#for one comment, it will be automatically loaded into the object
								# for different comments, load it separately
								unless comments.blank?
									timeEntry.comments = comments[k].blank? ? nil : comments[k]	
								end
								#timeEntry.hours = hours[j].blank? ? nil : hours[j].to_f
								#to allow for internationalization on decimal separator
								timeEntry.hours = hours[j].blank? ? nil : hours[j].gsub(decimal_separator, '.').to_f
								
								unless custom_fields.blank?
									timeEntry.custom_field_values.each do |custom_value|
										custom_field = custom_value.custom_field

										#if it is from the row, it should be automatically loaded
										if !((!Setting.plugin_redmine_wktime['wktime_enter_cf_in_row1'].blank? &&
											Setting.plugin_redmine_wktime['wktime_enter_cf_in_row1'].to_i == custom_field.id) ||
											(!Setting.plugin_redmine_wktime['wktime_enter_cf_in_row2'].blank? &&
											Setting.plugin_redmine_wktime['wktime_enter_cf_in_row2'].to_i == custom_field.id))
											if use_detail_popup
												cvs = custom_values[custom_field.id]
												custom_value.value = cvs[k].blank? ? nil : 
												custom_field.multiple? ? cvs[k].split(',') : cvs[k]	
											end
										end
									end
								end
								
								@entries << timeEntry	
							end
							j += 1
						end				
					end
				end
			end
		end
  end

def gatherWkCustomFields(wktime)
	cvParams = nil
	wktimeParams = params[:wktime]
	cvParams = wktimeParams[:custom_field_values] unless wktimeParams.blank?
	custom_values = Hash.new
	custom_fields = WktimeCustomField.find(:all)					
	
	if !custom_fields.blank? && !cvParams.blank?
		wktime.custom_field_values.each do |custom_value|
			custom_field = custom_value.custom_field

			cvs = cvParams["#{custom_field.id}"]
			custom_value.value = cvs.blank? ? nil : 
				custom_field.multiple? ? cvs.split(',') : cvs									
		end
	end
	
end

  
	def findEntries
		setup
		cond = getCondition('spent_on', @user.id, @mon, @mon+6)
		TimeEntry.find(:all, :conditions => cond,
			:order => 'project_id, issue_id, activity_id, spent_on')
	end
	
	def findWktime(start_date, end_date=nil)
		setup
		cond = getCondition('begin_date', @user.nil? ? nil : @user.id, start_date, end_date)		
		@wktimes = Wktime.find(:all, :conditions => cond)
		@wktime = @wktimes[0] unless @wktimes.blank? 
	end
	
	def findWktimeHash(start_date, end_date)
		@wktimesHash ||= Hash.new
		@wktimesHash.clear
		findWktime(start_date, end_date)		
		@wktimes.each do |wktime|
			@wktimesHash[wktime.user_id.to_s + wktime.begin_date.to_s] = wktime
		end
	end
	
	def render_edit
		set_user_projects
		render :action => 'edit', :user_id => params[:user_id], :mon => @mon
	end
	
  def check_perm_and_redirect
    unless check_permission
      render_403
      return false
    end
  end
  
  def user_allowed_to?(privilege, entity)
	setup
	return @user.allowed_to?(privilege, entity)
  end
  
  def can_log_time?(project_id)
	ret = false
	set_loggable_projects
	@logtime_projects.each do |lp|
		if lp.id == project_id
			ret = true
			break
		end
	end
	return ret
  end
  
  def check_permission
	set_user_projects
    return !@logtime_projects.blank?
  end
  
    def check_editperm_redirect
		unless check_editPermission
			render_403
			return false
		end
	end
  
    def check_editPermission
		allowed = true;
		ids = params['ids']
		if !ids.blank?
			@entries = TimeEntry.find(ids)
		else
			setup
			cond = getCondition('spent_on', @user.id, @mon, @mon+6)
			@entries = TimeEntry.find(:all, :conditions => cond)
		end
		@entries.each do |entry|
			if(!entry.editable_by?(User.current))
				allowed = false
				break
			end
		end
		return allowed
	end

def updateEntry(entry)  
	errorMsg = nil
	if entry.hours.blank?
		# delete the time_entry
		# if the hours is empty but id is valid
		# entry.destroy() unless ids[i].blank?
		if !entry.id.blank?
			if !entry.destroy()
				errorMsg = entry.errors.full_messages.join('\n')
			end
		end
	else
		#if id is there it should be update otherwise create
		#the UI disables editing of 
		if can_log_time?(entry.project_id)
			if !entry.save()
				errorMsg = entry.errors.full_messages.join('\n')
			end
		else
			errorMsg = l(:error_not_permitted_save)
		end
	end
	return errorMsg
end
  
def updateWktime
  	errorMsg = nil
	@wktime.begin_date = @mon
	@wktime.user_id = @user.id
	@wktime.statusupdater_id = User.current.id
	@wktime.statusupdate_on = Date.today
	if !@wktime.save()
		errorMsg = @wktime.errors.full_messages.join('\n')
	end
	return errorMsg
end

# update timesheet status
def updateStatus(status)
	errorMsg = nil
	if @wktimes.blank? 
		errorMsg = l(:error_wktime_save_nothing)
	else
		@wktime.statusupdater_id = User.current.id
		@wktime.statusupdate_on = Date.today
		@wktime.status = status
		if !@wktime.save()
			errorMsg = @wktime.errors.full_messages.join('\n')
		end
	end
	return errorMsg
end	

# delete a timesheet
def deleteWktime
	errorMsg = nil
	unless @wktime.nil? 
		if !@wktime.destroy()
			errorMsg = @wktime.errors.full_messages.join('\n')
		end
	end
	return errorMsg
end		
	
  # Retrieves the date range based on predefined ranges or specific from/to param dates
  def retrieve_date_range
    @free_period = false
    @from, @to = nil, nil

    if params[:period_type] == '1' || (params[:period_type].nil? && !params[:period].nil?)
      case params[:period].to_s
      when 'today'
        @from = @to = Date.today
      when 'yesterday'
        @from = @to = Date.today - 1
      when 'current_week'
        @from = Date.today - (Date.today.cwday - 1)%7
        @to = @from + 6
      when 'last_week'
        @from = Date.today - 7 - (Date.today.cwday - 1)%7
        @to = @from + 6
      when '7_days'
        @from = Date.today - 7
        @to = Date.today
      when 'current_month'
        @from = Date.civil(Date.today.year, Date.today.month, 1)
        @to = (@from >> 1) - 1
      when 'last_month'
        @from = Date.civil(Date.today.year, Date.today.month, 1) << 1
        @to = (@from >> 1) - 1
      when '30_days'
        @from = Date.today - 30
        @to = Date.today
      when 'current_year'
        @from = Date.civil(Date.today.year, 1, 1)
        @to = Date.civil(Date.today.year, 12, 31)
      end
    elsif params[:period_type] == '2' || (params[:period_type].nil? && (!params[:from].nil? || !params[:to].nil?))
      begin; @from = params[:from].to_s.to_date unless params[:from].blank?; rescue; end
      begin; @to = params[:to].to_s.to_date unless params[:to].blank?; rescue; end
      @free_period = true
    else
      # default
	  # 'current_month'		
        @from = Date.civil(Date.today.year, Date.today.month, 1)
        @to = (@from >> 1) - 1
    end    
    
    @from, @to = @to, @from if @from && @to && @from > @to

  end  


  	def setup
		unless params[:mon].blank?
			mon = params[:mon].to_s.to_date
			# if user has changed the monday
			@mon ||= getMonday(mon)
		end
		unless params[:user_id].blank?
			user_id = params[:user_id]
			@user ||= User.find(user_id)
		end
	end
  
	def set_user_projects
		set_managed_projects
		set_loggable_projects
	end
	
	def set_managed_projects
		@manage_projects ||= Project.find(:all, :order => 'name', 
			:conditions => Project.allowed_to_condition(User.current, :manage_members))
		selected_proj_id = params[:project_id]
		if !selected_proj_id.blank?
			sel_project = @manage_projects.select{ |proj| proj.id == selected_proj_id.to_i }	
			@selected_project ||= sel_project[0] if !sel_project.blank?
		else
			@selected_project ||= @manage_projects[0] if !@manage_projects.blank?
		end
	end

	def set_loggable_projects
		u_id = params[:user_id]
		if !u_id.blank?	&& u_id.to_i != 0
			@user ||= User.find(u_id)			
			@logtime_projects ||= Project.find(:all, :order => 'name', 
				:conditions => Project.allowed_to_condition(@user, :log_time))
		end
	end
	
	def set_project_issues(entries)
		@projectIssues ||= Hash.new
		@projActivities ||= Hash.new
		@projectIssues.clear
		@projActivities.clear
		entries.each do |entry|
			set_visible_issues(entry)
		end
		#load the first project in the list also
		set_visible_issues(nil)
	end

	def set_visible_issues(entry)
		project = entry.nil? ? (@logtime_projects.blank? ? nil : @logtime_projects[0]) : entry.project
		project_id = project.nil? ? 0 : project.id
		if @projectIssues[project_id].blank?
			allIssues = Array.new
			if Setting.plugin_redmine_wktime['wktime_closed_issue_ind'].to_i == 1
				allIssues = Issue.find_all_by_project_id(project_id)
			else
				allIssues = Issue.find_all_by_project_id(project_id,
							:conditions => ["#{IssueStatus.table_name}.is_closed = ? OR #{Issue.table_name}.updated_on >= ?", false, @mon],
							:include => :status)
			end
			# find the issues which are visible to the user
			@projectIssues[project_id] = allIssues.select {|i| i.visible?(@user) }
		end
		if @projActivities[project_id].blank?
			@projActivities[project_id] = project.activities unless project.nil?
		end

	end
	
end