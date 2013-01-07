function projChanged(projDropdown, userid, needBlankOption){
	var id = projDropdown.options[projDropdown.selectedIndex].value;
	var fmt = 'text';
	var userDropdown = document.getElementById("user_id");
	var userUrl = document.getElementById("getusers_url").value;
	   
	var $this = $(this);
	
	$.ajax({
		url: userUrl,
		type: 'get',
		data: {project_id: id, user_id: userid, format:fmt},
		success: function(data){ updateUserDD(data, userDropdown, userid, needBlankOption, false); },
		beforeSend: function(){ $this.addClass('ajax-loading'); },
		complete: function(){ $this.removeClass('ajax-loading'); }
	});
}

function updateUserDD(itemStr, dropdown, userid, needBlankOption, skipFirst)
{
	var items = itemStr.split('\n');
	var i, index, val, text, start;
	dropdown.options.length = 0;
	if(needBlankOption){
		dropdown.options[0] = new Option( "All Users", "0", false, false) 
	}
	for(i=0; i < items.length-1; i++){
		index = items[i].indexOf(',');
		if(skipFirst){
			if(index != -1){
				start = index+1;
				index = items[i].indexOf(',', index+1);
			}
		}else{
			start = 0;
		}
		if(index != -1){
			val = items[i].substring(start, index);
			text = items[i].substring(index+1);
			dropdown.options[needBlankOption ? i+1 : i] = new Option( 
				text, val, false, val == userid);
		}
	}
}
