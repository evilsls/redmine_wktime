  get 'wktime/index', :to => 'wktime#index'

  get 'wktime/getissues', :to => 'wktime#getissues'

  get 'wktime/getactivities', :to => 'wktime#getactivities'
  
  get 'wktime/getusers', :to => 'wktime#getusers'

  get 'wktime/deleterow', :to => 'wktime#deleterow'

  get 'wktime/export', :to => 'wktime#export'
  
  match 'wktime/edit', :to => 'wktime#edit', :via => [:get, :post]

  get 'wktime/new', :to => 'wktime#new'
			  
  post 'wktime/update', :to => 'wktime#update'
			  
  delete 'wktime/destroy', :to => 'wktime#destroy'
