require 'redmine'
require_dependency 'custom_fields_helper'

module WktimeHelperPatch
	def self.included(base) # :nodoc:
		base.send(:include, InstanceMethods)

		base.class_eval do
		  alias_method_chain :custom_fields_tabs, :wktime_tab
		end
	end

	module InstanceMethods
		# Adds a wktime tab to the custom fields administration page
		def custom_fields_tabs_with_wktime_tab
			tabs = custom_fields_tabs_without_wktime_tab
			# Code added to check if the tab already exist - to fix the multiple tab issue
			appendTab = true
			tabs.each do |tab|
				if tab[:name].eql? 'WktimeCustomField'
					appendTab = false
					break
				end
			end
			if appendTab			
				tabs << {:name => 'WktimeCustomField', :partial => 'custom_fields/index', :label => :label_wktime}
			end
			return tabs
		end
	end
end

CustomFieldsHelper.send(:include, WktimeHelperPatch)

Redmine::Plugin.register :redmine_wktime do
  name 'Weekly Timesheet'
  author 'Adhi Software Pvt Ltd'
  description 'This plugin is for entering weekly timesheet'
  version '1.3'
  url 'http://www.redmine.org/plugins/wk-time'
  author_url 'http://www.adhisoftware.co.in/'
  
  settings(:partial => 'settings',
           :default => {
             'wktime_project_dd_width' => '150',
             'wktime_issue_dd_width' => '250',
             'wktime_actv_dd_width' => '75',
			 'wktime_closed_issue_ind' => '0',
			 'wktime_restr_max_hour' => '0',
			 'wktime_max_hour_day' => '8',
			 'wktime_page_width' => '210',
			 'wktime_page_height' => '297',
			 'wktime_margin_top' => '20',
			 'wktime_margin_bottom' => '20',
			 'wktime_margin_left' => '10',
			 'wktime_margin_right' => '10',
			 'wktime_line_space' => '4',
			 'wktime_enter_issue_id' => '0',
			 'wktime_header_logo' => 'logo.jpg',
			 'wktime_work_time_header' => '0',
			 'wktime_allow_blank_issue' => '0',
			 'wktime_enter_comment_in_row' => '1',
 			 'wktime_use_detail_popup' => '0',
 			 'wktime_use_approval_system' => '0',
 			 'wktime_uuto_approve' => '0',			 
			 'wktime_submission_ack' => 'I Acknowledge that the hours entered are accurate to the best of my knowledge',
			 'wktime_enter_cf_in_row1' => '0',
			 'wktime_enter_cf_in_row2' => '0'


  })
  
  menu :top_menu, :wkTime, { :controller => 'wktime', :action => 'index' }, :caption => :label_wktime, :if => Proc.new { User.current.logged? }
end
