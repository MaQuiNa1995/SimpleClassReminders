if GetLocale() ~= "esES" and GetLocale() ~= "esMX" then return end

local _, addon = ...
addon.L = {
    NO_HEALTHSTONE 			= "¡ NO TIENES PIEDRA DE BRUJO !",
    NO_PET         			= "¡ NO TIENES MASCOTA INVOCADA !",
    NO_FORTITUDE   			= "¡ FALTA ENTEREZA EN EL GRUPO !",
    NO_DEVOTION    			= "¡ NO TIENES AURA DE DEVOCIÓN !",
	NO_LETHAL_POISON  		= "¡ SIN VENENO LETAL !",
	NO_NON_LETHAL_POISON 	= "¡ SIN VENENO NO LETAL !"
}
