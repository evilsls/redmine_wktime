$(document).ready(function(){	
	updateCustFldDD(document.getElementById('settings_wktime_enter_cf_in_row1'),'settings_wktime_enter_cf_in_row2');
	updateCustFldDD(document.getElementById('settings_wktime_enter_cf_in_row2'),'settings_wktime_enter_cf_in_row1');
});

function updateCustFldDD(currCFDD,anotherCFDD)
{
	var anotherCFDD_Value = document.getElementById(anotherCFDD).value;
	document.getElementById(anotherCFDD).length = 0; //clear the existing values	
	var templateDD = document.getElementById('template_custFldDD');
	var ddlength = templateDD.options.length;
	var j = 0;
	//Refill the dropdown
	for(i=0; i < ddlength; i++)
	{
		if(currCFDD.value != templateDD.options[i].value || currCFDD.value == 0)
		{
			document.getElementById(anotherCFDD).options[j] = new Option(templateDD.options[i].text,templateDD.options[i].value,false,templateDD.options[i].value == anotherCFDD_Value);
			j++;
		}
	}
}