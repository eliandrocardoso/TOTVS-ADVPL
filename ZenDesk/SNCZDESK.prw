#Include "fileio.ch"
#Include "protheus.ch"
#Include "TopConn.ch"
#INCLUDE "TBICONN.CH"

/*/{Protheus.doc} SNCZDESK
Rotina de execução via Schedule pra sincronização de informações com o ZenDesk
@type function
@version  
@author eliandrocardoso@gmail.com
@since 08/07/2021
@return variant, return_description
/*/
User Function SNCZDESK()
	************************
	Local bBlock:= ErrorBlock( { |e| fTrataErro(e) } )
	Local cSemaforo			:= "SNCZDESK"
	Local nHandler			:= 0

	Private cMsgFatalError := ""

	Begin Sequence

		RpcSetType(3)
		RpcSetEnv("01","01","","","FIN")

		If fSemaforo(cSemaforo, @nHandler)
			FWLogMsg("INFO","",'1',"JobIntZenDesk",,"JobIntZenDesk","Já existe um scheduler executando a rotina " + cSemaforo + ". O agendamento deste horário foi abortado.")
			Return
		End

		Private _cServ := AllTrim(GetMV("MV_RELSERV"))
		Private _cPass := AllTrim(GetMV("MV_RELPSW"))
		Private _cAcco := AllTrim(GetMV("MV_RELACNT"))


		FWLogMsg("INFO","",'1',"JobIntZenDesk",,"JobIntZenDesk","Iniciando JobIntZenDesk: "+cValToChar(dDataBase)+ ' ' +time())

		//Envia informações para o Zendesk
		fEnvia()

		//Recebe informações do ZenDesk
		fRecebe()

		FWLogMsg("INFO","",'1',"JobIntZenDesk",,"JobIntZenDesk","Finalizado Job de Sincronismo :"+cValToChar(dDataBase)+ ' ' +time())

		RpcClearEnv()

	End Sequence

	ErrorBlock(bBlock)

Return

/*/{Protheus.doc} fRecebe
Função responsável pela execução dos serviços que recebem informações do ZenDesk. 
@type function
@version  
@author eliandrocardoso@gmail.com
@since 08/07/2021
@return variant, return_description
/*/
Static Function fRecebe()
	*************************

	FWLogMsg("INFO","",'1',"JobIntZenDesk",,"fRecebe","Iniciando integração ZENDESK > ERP: "+cValToChar(dDataBase)+ ' ' +time())
	fSincTickets()
Return .T.

/*/{Protheus.doc} fEnvia
Função responsável pela execução dos serviços que enviam informações ao ZenDesk
@type function
@version  
@author eliandrocardoso@gmail.com
@since 08/07/2021
@return variant, return_description
/*/
Static Function fEnvia()
	*************************

	FWLogMsg("INFO","",'1',"JobIntZenDesk",,"fEnvia","Iniciando integração ERP > ZENDESK: "+cValToChar(dDataBase)+ ' ' +time())

	fSincTra() //Envia base de transportadoras para campo lista suspensa do zendesk

	fSincCli() //Envia base de clientes para o campo lista suspensa do zendesk
Return .T.

Static Function fTrataErro(e)
	*****************************
	Local cMessage := e:Description
	if e:gencode > 0
		FWLogMsg("INFO","",'1',"JobIntZenDesk",,"fTrataErro","ERRO SINCRONISMO ZenDesk: " + cMessage)
	Endif

	if Type("cMsgFatalError") <> "U"
		cMessage += cMsgFatalError
	Endif
	FWLogMsg("INFO","",'1',"JobIntZenDesk",,"fTrataErro",cMessage)
	fEnvMail(cMessage, "Erro Sincronismo ZenDesk Job","eliandrocardoso@gmail.com")

	RpcClearEnv()
	Break
Return

Static Function fEnvMail(cMensagem,cTitulo,cDestinat,cArquivo,cAccount, cRemeten)
	********************************************************************************
	Local cServer    := _cServ
	Local cPassword  := _cPass
	Default cAccount := _cAcco
	Default cRemeten := ""

	cMensagem := iIf(cMensagem == Nil,"Envio automático.",cMensagem)
	cTitulo   := iIf(cTitulo   == Nil,"Enviado automaticamente",cTitulo)
	cArquivo  := iIf(cArquivo  == Nil,"",cArquivo)

	Connect SMTP Server cServer Account cAccount Password cPassword Result lConectou

	MailAuth(cAccount, cPassword)

	Send Mail From cRemeten To cDestinat Subject cTitulo Body cMensagem Attachment cArquivo Result lEnviado

	cMensagem := "Sem comunicação com o servidor SMTP, cheque os parametros do sistema referente a SMTP!"

	Get Mail Error cMensagem
	//ConOut(cMensagem)
	FWLogMsg("INFO","",'1',"JobIntZenDesk",,"fEnvMail",cMensagem)

	Disconnect SMTP Server Result lDisConectou

Return lEnviado

/*/{Protheus.doc} fSincTickets
Sincroniza os Tickets do ZenDesk a tabela customizada
@type function
@version 12.1.25
@author Eliandro Cardoso
@since 28/06/2021
@return variant, return_description
/*/
Static Function fSincTickets()
	******************************
	Local nTimeOut 	:= 120
	Local aHeader 	:= {}
	Local cResult 	:= ""
	Local aChaves 	:= {}
	Local cGetUrl 	:= ""
	Local oRet
	Local lFimMov 	:= .F.
	Local dIDZenD   := ""
	Local lRet      := .T.
	Local oTicket   := Nil
	Local cLogin    := SuperGetMV("MV_ZUSUZDK",,0)//"Usuário do Zendesk: Deve informar usuario e senha separado por :. Exemplo: eliandrocardoso@gmail.com:12345678
	Local nEnd_Time := SuperGetMV("MV_ZDKUTIK",,0) //Parametro que armazena o último período de sincronismo com o Zendesk
	Local aCampos   := {}
	Local aForms    := {}

	//Formulários
	/*
	Por enquanto estou fixando os formulários no array, porém estarei implementando o sincronismo de formulários (tipos de formulários)
	A estrutura desse array compreende em:
	Coluna 01: ID do formulário no ZenDesk
	Coluna 02: Descrição do tipo do formulário
	*/
	aadd(aForms,{360001330171, "RECLAMACAO AVARIA"})
	aadd(aForms,{360001277151, "RECLAMACAO ATRASO ENTREGA"})
	aadd(aForms,{360001277431, "ERRO TRANSPORTADORA"})
	aadd(aForms,{360001265612, "ERRO CARREGAMENTO"})
	aadd(aForms,{360001246412, "EMAIL PADRAO"})
	aadd(aForms,{360001276291, "PROBLEMA COMERCIAL"})
	aadd(aForms,{360001276351, "ERRO DE PRODUCAO"})
	aadd(aForms,{360001277031, "PROBLEMA IMOBILIARIA"})
	aadd(aForms,{360001276971, "PROBLEMA AUTOMOTIVO"})
	aadd(aForms,{360001265052, "PROBLEMA CARBON"})
	aadd(aForms,{360001276931, "PROBLEMA UNIDADE 2"})
	aadd(aForms,{360001277011, "PROBLEMA FLEXOGRAFICA"})
	aadd(aForms,{360001277131, "PROBLEMA SOLVENTES"})
	aadd(aForms,{360001376511, "PROBLEMA AUTOMOTIVA"})
	aadd(aForms,{360001375991, "PROBLEMA IMOBILIARIA"})
	aadd(aForms,{360001274491, "FORM IMOBILIARIA"})
	aadd(aForms,{360001274471, "FORM AVARIA"})
	aadd(aForms,{360001439431, "LIGACAO"})


	/*
	A estrutura desse array compreende em:
	Coluna 01: ID do campo de Ticket no Zendesk
	Coluna 02: Nome do campo do protheus que receberá essa informação
	*/
	//Amarração dos campos customizados do ZenDesck com o Protheus
	aadd(aCampos,{360038318092,"Z92_PRIOR"})  //Prioridade
	aadd(aCampos,{360038318072,"Z92_TIPO"})   //Tipo
	aadd(aCampos,{360038318052,"Z92_STATUS"}) //Status Atendimento
	aadd(aCampos,{360038318032,"Z92_DESCRI"}) //Descrição Customizada
	aadd(aCampos,{360038318012,"Z92_ASSUNT"}) //Assunto
	aadd(aCampos,{360039343831,"Z92_NOMRES"}) //Responsável
	aadd(aCampos,{360039343871,"Z92_NOTA"})   //Nota Fiscal
	aadd(aCampos,{360039413932,"Z92_MOTIVO"}) //Motivo
	aadd(aCampos,{360039344351,"Z92_FORSOL"}) //Forma Solucao
	aadd(aCampos,{360039344871,"Z92_DESDET"}) //Descriçaõ detalhada
	aadd(aCampos,{360039344891,"Z92_LOTE"})   // Lote
	aadd(aCampos,{360039414472,"Z92_VALID"})  //Validade
	aadd(aCampos,{360039414492,"Z92_QTDPRD"}) //Quantidade do Produto
	aadd(aCampos,{360039345271,"Z92_FORNEB"}) //Fornecedor Embalagem
	aadd(aCampos,{360039345451,"Z92_PROBEB"}) //Embalagem apresenta problema
	aadd(aCampos,{360039369631,"Z92_CNPJ"})   //CNPJ
	aadd(aCampos,{360039369931,"Z92_FONE"})   //Telefone
	aadd(aCampos,{360039433972,"Z92_TPSUBS"}) //Tipo Substrato
	aadd(aCampos,{360039370171,"Z92_FUNAPL"}) //Fundo Aplicado
	aadd(aCampos,{360039370231,"Z92_TINAPL"}) //Tinta Aplicada
	aadd(aCampos,{360039370251,"Z92_LOCAPL"}) //Local Aplicado
	aadd(aCampos,{360039370311,"Z92_DILUIC"}) //Diluição
	aadd(aCampos,{360039370711,"Z92_FORAPL"}) //Forma Aplicação
	aadd(aCampos,{360039434432,"Z92_DFORPL"}) //Descrição Forma Aplicação
	aadd(aCampos,{360039434652,"Z92_QTDDM"}) //Quantidade de demãos
	aadd(aCampos,{360039434852,"Z92_TEMMOD"}) //Tem mão de obra
	aadd(aCampos,{360039370991,"Z92_VLRMOD"}) //Valor Mão de obra
	aadd(aCampos,{360039435312,"Z92_TIPAPL"}) //Tipo Aplicacao
	aadd(aCampos,{360039435472,"Z92_CATALI"}) //Catalizador
	aadd(aCampos,{360039371911,"Z92_DILSOL"}) //Diluição Solvente
	aadd(aCampos,{360039435972,"Z92_SUPAPL"}) //Superficie Aplicada
	aadd(aCampos,{360039372811,"Z92_QSUPAP"}) //Qual Superfície aplicada
	aadd(aCampos,{360039372831,"Z92_PINTUR"}) //Pintura
	aadd(aCampos,{360039373311,"Z92_TRTSUP"}) //Tratamento Superfície
	aadd(aCampos,{360039436492,"Z92_QTRSUP"}) //Qual tratamento superfície
	aadd(aCampos,{360039374431,"Z92_JAENT"})  //Entrega já foi feita?
	aadd(aCampos,{360039437252,"Z92_DATENT"}) //Data Entrega
	aadd(aCampos,{360039374491,"Z92_SOLPRO"}) //Solicitar Prorrogação
	aadd(aCampos,{360039375011,"Z92_NOMTRA"}) //Nome Transportadora
	aadd(aCampos,{360039375051,"Z92_SUGTRT"}) //Sugestão tratativa
	aadd(aCampos,{360039375071,"Z92_QSUGTR"}) //Qual Sugestâo tratativa
	aadd(aCampos,{360039375111,"Z92_FZNCTE"}) //Fez anotação no CTE?
	aadd(aCampos,{360039439832,"Z92_MERCAD"}) //Mercadoria
	aadd(aCampos,{360039498932,"Z92_CNPJ2"})  //CNPJ 2
	aadd(aCampos,{360039473531,"Z92_ALTPRZ"}) //Alteração Prazo
	aadd(aCampos,{360039597931,"Z92_PROCED"}) //Procedência
	aadd(aCampos,{360040894072,"Z92_PRODS"})  //Produtos
	aadd(aCampos,{360041013892,"Z92_VLRIND"}) //Valor Indenização
	aadd(aCampos,{360041321651,"Z92_CODCLI"}) //Código do Cliente
	aadd(aCampos,{360041323831,"Z92_MUNEST"}) //Cidade e Estado
	aadd(aCampos,{360041368652,"Z92_DETRES"}) //Detalhe Resumido
	aadd(aCampos,{360041480992,"Z92_DETOCO"}) //Detalhe Ocorrência
	aadd(aCampos,{360041445051,"Z92_RNC"})    //RNC
	aadd(aCampos,{360041445231,"Z92_CC"})     //Centro de Custo
	aadd(aCampos,{360041551372,"Z92_OBSGER"}) //Observações gerais
	aadd(aCampos,{360045260271,"Z92_CLILOJ"}) //Cliente / Loja ERP
	aadd(aCampos,{360045239312,"Z92_TRANSP"}) //Transportdora ERP

	aadd(aHeader,'User-Agent: PostmanRuntime/7.28.1')
	aadd(aHeader,'Content-Type: application/json')
	aadd(aHeader,'Authorization: Basic ' + Encode64(cLogin))

	cStartTime := ""
	While !lFimMov
		oRet := nil
		lRet := .T.

		cUrl := fZenUrl()
		cPath := "v2/incremental/tickets.json?start_time="+cValToChar(nEnd_Time)
		oRest := FWRest():New(cUrl)
		oRest:setPath(cPath)

		oRest:nTimeOut := 10000
		If oRest:Get(aHeader)
			cResult := oRest:GetResult()
			FWJsonDeserialize(cResult,@oTicket)

			lFimMov := oTicket:End_of_Stream
			nEnd_Time := oTicket:End_time
			cNextPage := oTicket:Next_page

			For nTicket := 1 to Len(oTicket:Tickets)
				nIdTIcket := oTicket:Tickets[nTicket]:id
				nPForm := aScan(aForms,{|x| x[1] == oTicket:Tickets[nTicket]:ticket_form_id})
				Z92->(dbSetOrder(1))
				if !Z92->(dbSeek(xFilial("Z92") + StrZero(nIdTicket,20)))
					RecLock("Z92",.T.)
					Z92->Z92_FILIAL := xFilial("Z92")
					Z92->Z92_ID     := StrZero(nIdTicket,20)
					Z92->Z92_DESCRP := fToTexto(oTicket:Tickets[nTicket]:DESCRIPTION)
					Z92->Z92_FORMID := cValToChar(oTicket:Tickets[nTicket]:ticket_form_id)
					if nPForm > 0
						Z92->Z92_TIPREG := aForms[nPForm][2]
					Endif
					if !Empty(oTicket:Tickets[nTicket]:STATUS)
						Z92->Z92_STATUS := Upper(fToTexto(oTicket:Tickets[nTicket]:STATUS))
					Endif
					if !Empty(oTicket:Tickets[nTicket]:TYPE)
						Z92->Z92_TYPE   := Upper(fToTexto(oTicket:Tickets[nTicket]:TYPE))
					Endif
					if Type("oTicket:Tickets[nTicket]:CREATED_AT") <> "U"
						Z92->Z92_LOGINC := oTicket:Tickets[nTicket]:CREATED_AT
					Endif
					if Type("oTicket:Tickets[nTicket]:UPDATED_AT") <> "U"
						Z92->Z92_LOGATU := oTicket:Tickets[nTicket]:UPDATED_AT
					Endif
					Z92->Z92_URL    := oTicket:Tickets[nTicket]:URL
					if !Empty(oTicket:Tickets[nTicket]:PRIORITY)
						Z92->Z92_PRIOR  := Upper(fToTexto(oTicket:Tickets[nTicket]:PRIORITY))
					Endif
					For i := 1 to Len(oTicket:Tickets[nTicket]:FIELDS)
						if !Empty(oTicket:Tickets[nTicket]:FIELDS[i]:VALUE)
							nPCampo := aScan(aCampos,{|x| x[1] == oTicket:Tickets[nTicket]:FIELDS[i]:ID})
							If nPCampo > 0
								cCampo := aCampos[nPCampo][2]
								if GetSx3Cache(cCampo,"X3_TIPO") == "D"
									Z92->(&cCampo) := SToD(StrTran(oTicket:Tickets[nTicket]:FIELDS[i]:VALUE,"-",""))
								Elseif GetSx3Cache(cCampo,"X3_TIPO") == "N"
									Z92->(&cCampo) := Val(oTicket:Tickets[nTicket]:FIELDS[i]:VALUE)
								Else
									Z92->(&cCampo) := Upper(fToTexto(oTicket:Tickets[nTicket]:FIELDS[i]:VALUE))
								Endif
							Endif
						Endif
					Next i
					Z92->(MsUnLock())
				Elseif AllTrim(Z92->Z92_LOGATU) <> AllTrim(oTicket:Tickets[nTicket]:UPDATED_AT)
					RecLock("Z92",.F.)
					Z92->Z92_DESCRP := fToTexto(oTicket:Tickets[nTicket]:DESCRIPTION)
					Z92->Z92_FORMID := cValToChar(oTicket:Tickets[nTicket]:ticket_form_id)
					if nPForm > 0
						Z92->Z92_TIPREG := aForms[nPForm][2]
					Endif
					if !Empty(oTicket:Tickets[nTicket]:STATUS)
						Z92->Z92_STATUS := Upper(fToTexto(oTicket:Tickets[nTicket]:STATUS))
					Endif
					if !Empty(oTicket:Tickets[nTicket]:TYPE)
						Z92->Z92_TYPE   := Upper(fToTexto(oTicket:Tickets[nTicket]:TYPE))
					Endif
					if Type("oTicket:Tickets[nTicket]:CREATED_AT") <> "U"
						Z92->Z92_LOGINC := oTicket:Tickets[nTicket]:CREATED_AT
					Endif
					if Type("oTicket:Tickets[nTicket]:UPDATED_AT") <> "U"
						Z92->Z92_LOGATU := oTicket:Tickets[nTicket]:UPDATED_AT
					Endif
					Z92->Z92_URL    := oTicket:Tickets[nTicket]:URL
					if !Empty(oTicket:Tickets[nTicket]:PRIORITY)
						Z92->Z92_PRIOR  := Upper(fToTexto(oTicket:Tickets[nTicket]:PRIORITY))
					Endif
					For i := 1 to Len(oTicket:Tickets[nTicket]:FIELDS)
						if !Empty(oTicket:Tickets[nTicket]:FIELDS[i]:VALUE)
							nPCampo := aScan(aCampos,{|x| x[1] == oTicket:Tickets[nTicket]:FIELDS[i]:ID})
							If nPCampo > 0
								cCampo := aCampos[nPCampo][2]
								if GetSx3Cache(cCampo,"X3_TIPO") == "D"
									Z92->(&cCampo) := SToD(StrTran(oTicket:Tickets[nTicket]:FIELDS[i]:VALUE,"-",""))
								Elseif GetSx3Cache(cCampo,"X3_TIPO") == "N"
									Z92->(&cCampo) := Val(oTicket:Tickets[nTicket]:FIELDS[i]:VALUE)
								Else
									Z92->(&cCampo) := Upper(fToTexto(oTicket:Tickets[nTicket]:FIELDS[i]:VALUE))
								Endif
							Endif
						Endif
					Next i
					Z92->(MsUnLock())
				Endif
			Next nTicket
		Endif

	EndDo

	PutMv("MV_ZDKUTIK",nEnd_Time)

Return .T.

/*/{Protheus.doc} fZenUrl
Retorna a URL da API do ZenDesk
@type function
@version 12.1.25
@author Eliandro Cardoso
@since 28/06/2021
@return variant, return_description
/*/
Static function fZenUrl()
	*****************************
	Local cUrl := "https://suaempresa.zendesk.com/api/";

Return cUrl

/*/{Protheus.doc} fSincTra
Sincronização de informações de transportadora com campo de ticket customizado no Zendesk
@type function
@version  
@author eliandrocardoso@gmail.com	
@since 08/07/2021
@return variant, return_description
/*/
Static Function fSincTra()
	***************************
	Local nTimeOut 	:= 120
	Local aHeader 	:= {}
	Local cResult 	:= ""
	Local aChaves 	:= {}
	Local cGetUrl 	:= ""
	Local oReturn   := Nil
	Local cLogin    := SuperGetMV("MV_ZUSUZDK",,0)//"Usuário do Zendesk: Deve informar usuario e senha separado por :. Exemplo: eliandrocardoso@gmail.com:12345678
	Local cIDCampo  := "360045239312" //ID do campo 'Transportadora ERP' lá do Zendesk
	Local cBody     := ""
	Local cUrl      := fZenUrl()
	Local cPath     := "v2/ticket_fields/"+cIdCampo+"/options.json"
	Local lUPDATE   := .F. //Por padrão, só inclui item novo. Deixei pronto para caso queira atualizar, basta mudar essa variavel para TRUE

	aadd(aHeader,'User-Agent: PostmanRuntime/7.28.1')
	aadd(aHeader,'Content-Type: application/json')
	aadd(aHeader,'Authorization: Basic ' + Encode64(cLogin))

	SA4->(dbSetOrder(1))
	SA4->(dbSeek(xFilial("SA4")))
	While SA4->(!EOF()) .and. SA4->A4_FILIAL == xFilial("SA4")
		oReturn := nil
		oRest  := nil

		if SA4->A4_MSBLQL <> '1'
			if lUPDATE
				oRest := FWRest():New(cUrl)
				oRest:setPath(cPath)
				If Empty(SA4->A4_ZIDZDSK)
					cBody := '{"custom_field_option": {"name":"'+AllTrim(NoAcento(SA4->A4_NOME)) + ' (' + Transform(SA4->A4_CGC,"@R 99.999.999/9999-99")+')'+'","value":"'+AllTrim(SA4->A4_COD)+'"}}'
				Else
					cBody := '{"custom_field_option": {"id":"'+AllTrim(SA4->A4_ZIDZDSK)+'", "name":"'+AllTrim(NoAcento(SA4->A4_NOME)) + ' (' + Transform(SA4->A4_CGC,"@R 99.999.999/9999-99")+')'+'","value":"'+AllTrim(SA4->A4_COD)+'"}}'
				Endif
				oRest:SetPostParams(cBody)
				oRest:SetChkStatus(.F.)

				oRest:nTimeOut := 10000
				If oRest:Post(aHeader)
					cResult := oRest:GetResult()
					FWJsonDeserialize(cResult,@oReturn)
					RecLock("SA4",.F.)
					SA4->A4_ZIDZDSK := cValToChar(oReturn:CUSTOM_FIELD_OPTION:id) //Campo ID da transportado no Zendesk
					SA4->(MsUnLock())
				Endif
			Else
				If Empty(SA4->A4_ZIDZDSK)
					oRest := FWRest():New(cUrl)
					oRest:setPath(cPath)
					cBody := '{"custom_field_option": {"name":"'+AllTrim(NoAcento(SA4->A4_NOME)) + ' (' + Transform(SA4->A4_CGC,"@R 99.999.999/9999-99")+')'+'","value":"'+AllTrim(SA4->A4_COD)+'"}}'

					oRest:SetPostParams(cBody)
					oRest:SetChkStatus(.F.)

					oRest:nTimeOut := 10000
					If oRest:Post(aHeader)
						cResult := oRest:GetResult()
						FWJsonDeserialize(cResult,@oReturn)
						RecLock("SA4",.F.)
						SA4->A4_ZIDZDSK := cValToChar(oReturn:CUSTOM_FIELD_OPTION:id)
						SA4->(MsUnLock())
					Endif
				Endif
			Endif
		Endif
		SA4->(dbSkip())
	EndDo


Return

/*/{Protheus.doc} fSincCli
Sincronização de informações de cliente com campo de ticket customizado no Zendesk
@type function
@version  
@author elian
@since 08/07/2021
@return variant, return_description
/*/
Static Function fSincCli()
	***************************
	Local nTimeOut 	:= 120
	Local aHeader 	:= {}
	Local cResult 	:= ""
	Local aChaves 	:= {}
	Local cGetUrl 	:= ""
	Local oReturn   := Nil
	Local cLogin    := SuperGetMV("MV_ZUSUZDK",,0)//"Usuário do Zendesk: Deve informar usuario e senha separado por :. Exemplo: eliandrocardoso@gmail.com:12345678
	Local cIDCampo  := "360045260271" //ID do campo 'Cliente ERP' lá do Zendesk
	Local cBody     := ""
	Local cUrl      := fZenUrl()
	Local cPath     := "v2/ticket_fields/"+cIdCampo+"/options.json"
	Local lUPDATE   := .F. //Por padrão, só inclui item novo. Deixei pronto para caso queira atualizar, basta mudar essa variavel para TRUE

	aadd(aHeader,'User-Agent: PostmanRuntime/7.28.1')
	aadd(aHeader,'Content-Type: application/json')
	aadd(aHeader,'Authorization: Basic ' + Encode64(cLogin))
	//aadd(aHeader,'Authorization: Basic ' + Encode64("eliandro.cardoso@outlook.com:YJ4#YX#mtb5mYhV"))

	SA1->(dbSetOrder(1))
	SA1->(dbSeek(xFilial("SA1")))
	While SA1->(!EOF()) .and. SA1->A1_FILIAL == xFilial("SA1")
		oReturn := nil
		oRest  := nil
		if SA1->A1_MSBLQL <> '1'
			if lUPDATE
				oRest := FWRest():New(cUrl)
				oRest:setPath(cPath)
				If Empty(SA1->A1_ZIDZDSK)
					cBody := '{"custom_field_option": {"name":"'+AllTrim(SA1->(A1_COD + '/' + A1_LOJA)) + '-' + AllTrim(NoAcento(SA1->A1_NOME)) + '","value":"'+AllTrim(SA1->(A1_COD+A1_LOJA))+'"}}'
				Else
					cBody := '{"custom_field_option": {"id":"'+AllTrim(SA1->A1_ZIDZDSK)+'", "name":"'+AllTrim(SA1->(A1_COD + '/' + A1_LOJA)) + '-' + AllTrim(NoAcento(SA1->A1_NOME)) + '","value":"'+AllTrim(SA1->(A1_COD+A1_LOJA))+'"}}'
				Endif
				oRest:SetPostParams(cBody)
				oRest:SetChkStatus(.F.)

				oRest:nTimeOut := 10000
				If oRest:Post(aHeader)
					cResult := oRest:GetResult()
					FWJsonDeserialize(cResult,@oReturn)
					RecLock("SA1",.F.)
					SA1->A1_ZIDZDSK := cValToChar(oReturn:CUSTOM_FIELD_OPTION:id) //Campo customizado para armazenar o ID do cliente no Zendesk
					SA1->(MsUnLock())
				Endif
			Else
				If Empty(SA1->A1_ZIDZDSK)
					oRest := FWRest():New(cUrl)
					oRest:setPath(cPath)
					cBody := '{"custom_field_option": {"name":"'+AllTrim(SA1->(A1_COD + '/' + A1_LOJA)) + '-' + AllTrim(NoAcento(SA1->A1_NOME)) + '","value":"'+AllTrim(SA1->(A1_COD+A1_LOJA))+'"}}'
					oRest:SetPostParams(cBody)
					oRest:SetChkStatus(.F.)

					oRest:nTimeOut := 10000
					If oRest:Post(aHeader)
						cResult := oRest:GetResult()
						FWJsonDeserialize(cResult,@oReturn)
						RecLock("SA1",.F.)
						SA1->A1_ZIDZDSK := cValToChar(oReturn:CUSTOM_FIELD_OPTION:id) //Campo customizado para armazenar o ID do cliente no Zendesk
						SA1->(MsUnLock())
					Endif
				Endif
			Endif
		Endif
		
		SA1->(dbSkip())
	EndDo


Return

/*/{Protheus.doc} fSemaforo
Rotina para controle de semaforo. Garante que, se a rotina estiver em execução, não iniciará novo processo.
@type function
@version 12.1.25
@author eliandrocardoso@gmail.com
@since 08/07/2021
@param cSemaforo, character, Nome do arquivo de semaforo
@param nHandler, numeric, id do arquivo de semaforo
@return variant, return_description
/*/
Static Function fSemaforo(cSemaforo, nHandler)
	*******************************************
	Local cFile := "SNKSEMAFORO_" + cSemaforo + ".lck" //Coloque o nome do Job no lugar do XXX

	If File(cFile)
		nHandler := FOpen(cFile,FO_DENYREAD)
	Else
		nHandler := FCreate(cFile)
	End

	If nHandler > 0
		Return .F.
	End

Return .T.


Static Function NoAcento(cString)

	Local cChar	:= ""
	Local cVogal	:= "aeiouAEIOU"
	Local cAgudo	:= "áéíóú"+"ÁÉÍÓÚ"
	Local cCircu	:= "âêîôû"+"ÂÊÎÔÛ"
	Local cTrema	:= "äëïöü"+"ÄËÏÖÜ"
	Local cCrase	:= "àèìòù"+"ÀÈÌÒÙ"
	Local cTio		:= "ãõÃÕ"
	Local cCecid	:= "çÇ"
	Local cMaior	:= "&lt;"
	Local cMenor	:= "&gt;"
	Local cEcom		:= "&"

	Local nX		:= 0
	Local nY		:= 0

	For nX:= 1 To Len(cString)
		cChar:=SubStr(cString, nX, 1)
		IF cChar$cAgudo+cCircu+cTrema+cCecid+cTio+cCrase+cEcom
			nY:= At(cChar,cAgudo)
			If nY > 0
				cString := StrTran(cString,cChar,SubStr(cVogal,nY,1))
			EndIf
			nY:= At(cChar,cCircu)
			If nY > 0
				cString := StrTran(cString,cChar,SubStr(cVogal,nY,1))
			EndIf
			nY:= At(cChar,cTrema)
			If nY > 0
				cString := StrTran(cString,cChar,SubStr(cVogal,nY,1))
			EndIf
			nY:= At(cChar,cCrase)
			If nY > 0
				cString := StrTran(cString,cChar,SubStr(cVogal,nY,1))
			EndIf
			nY:= At(cChar,cTio)
			If nY > 0
				cString := StrTran(cString,cChar,SubStr("aoAO",nY,1))
			EndIf
			nY:= At(cChar,cCecid)
			If nY > 0
				cString := StrTran(cString,cChar,SubStr("cC",nY,1))
			EndIf
			nY:= At(cChar,cEcom)
			If nY > 0
				cString := StrTran(cString,cChar,SubStr("eE",nY,1))
			EndIf
		Endif
	Next

	If cMaior$ cString
		cString := strTran( cString, cMaior, "" )
	EndIf
	If cMenor$ cString
		cString := strTran( cString, cMenor, "" )
	EndIf

	For nX:=1 To Len(cString)
		cChar:=SubStr(cString, nX, 1)
		If (Asc(cChar) < 32 .Or. Asc(cChar) > 123) .and. !cChar $ '|'
			cString:=StrTran(cString,cChar,".")
		Endif
	Next nX

Return cString

Static Function fToTexto(cTexto)
	Local cRet := ""

	if !Empty(cTexto)
		if Type('DecodeUtf8(cTexto,"cp1252")') == "C"
			cRet := AllTrim(NoAcento(DecodeUtf8(cTexto,"cp1252")))
		Else
			cRet := AllTrim(NoAcento((cTexto)))
		Endif
	Endif

Return cRet