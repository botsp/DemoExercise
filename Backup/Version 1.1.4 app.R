#Failed version, cannot pass `data=` to `moudules=` in `init()`
library(teal)
library(haven)
library(teal.data)
library(teal.modules.general)
library(teal.modules.clinical)
library(sparkline)
library(readr)  # Reading CSV files
library(readxl) # Reading Excel files

options(shiny.useragg = FALSE)
# File size set to 120MB
options(shiny.maxRequestSize = 120*1024^2)
########################################################################################
## App header and footer ----
nest_logo <- "https://raw.githubusercontent.com/insightsengineering/hex-stickers/main/PNG/nest.png"

header <- tags$span(
  style = "display: flex; align-items: center; justify-content: space-between; margin: 10px 0 10px 0;",
  tags$span("TabulationViewer Demo App", style = "font-size: 25px;"),
  tags$span(
    style = "display: flex; align-items: center;",
    tags$img(src = nest_logo, alt = "NEST logo", height = "45px", style = "margin-right:10px;"),
    tags$span(style = "font-size: 24px;", "NEST @TabViewer")
  )
)

footer <- tags$p(style = "font-family: Arial, sans-serif; font-size: 13px;",
                 "This demo app is developed from the NEST Team at Roche/Genentech.
        For more information, please contact the developer: progsupp89@gmail.com"
)
########################################################################################
# Self-defined function
#Import sort_key that attached with sas datasets
import_sort_list <- function(file_path, sheet_name = "Sheet1", column_label = "Column_Name") {
  # Read the Excel file
  SortInfo <- read_excel(file_path, sheet = sheet_name)
  
  # Filter specific column
  SortInfo_srt <- subset(SortInfo, namelabel == column_label)
  
  # Create an empty list to store vectors
  vectors_list <- list()
  
  # Iterate through each row and create named vectors
  for (i in 1:nrow(SortInfo_srt)) {
    row_data <- SortInfo_srt[i, ]
    memname <- row_data$memname
    
    # Extract columns with prefix COL and remove NA values
    vector_values <- unlist(row_data[grepl("^COL", names(row_data))])
    vector_values <- vector_values[!is.na(vector_values)]
    
    # Store the vector in the list, without keeping column names
    vectors_list[[memname]] <- unname(vector_values)
  }
  
  # Return the result
  return(vectors_list)
}

# To generate join_key objects
generate_join_keys <- function(sort_list) {
  # Check if sort_list is "NOT UPLOADED"
  if (identical(sort_list, "NOT UPLOADED")) {
    return(join_keys())
  }
  # Convert vector names to lowercase for comparison
  names_lower <- tolower(names(sort_list))
  
  # Check if it is adsl(ADaM) or dm(SDTM)
  center_dataset <- if ("adsl" %in% names_lower) names(sort_list)[which(names_lower == "adsl")] else names(sort_list)[which(names_lower == "dm")]
  
  primary_keys <- lapply(names(sort_list), function(name) {
    do.call(join_key, list(name, keys = sort_list[[name]]))
  })
  
  foreign_keys <- lapply(setdiff(names(sort_list), center_dataset), function(name) {
    do.call(join_key, list(center_dataset, name, keys = c("STUDYID", "USUBJID")))
  })
  
  all_keys <- c(primary_keys, foreign_keys)
  
  do.call(join_keys, all_keys)
}
# Create Basic Modules
modules_list <<- list(
  tm_front_page(
    label = "App Info",
    header_text = c("Info about input data source" = "This app enables the upload of data files from the local drive."),
    tables = list(`NEST packages used in this demo app` = data.frame(
      Packages = c(
        "teal.modules.general",
        "teal.modules.clinical",
        "haven"
      )
    ))
  ),
  # tm_data_table("Data Table"),
  tm_variable_browser("Variable Browser")
)
choose_modules <- function(file_names) {
  # 在函数开始处获取文件名
  file_names_adj <- file_names
  ml <- list()
  # 检查文件名是否包含"ADSL"或"DM"
  if (any(sapply(c("ADSL", "DM"), function(x) any(grep(x, file_names_adj, ignore.case = TRUE))))) {
    # 如果文件名包含"ADSL"或"DM"，那么modules应该包含tm_data_table模块
    ml<-list(tm_data_table("Data Table"))
  } else {
    # 如果文件名不包含"ADSL"或"DM"，那么modules应该包含其他模块
    ml<-list(
      tm_front_page(
        label = "App Info",
        header_text = c("Info about input data source" = "This app enables the upload of data files from the local drive."),
        tables = list(`NEST packages used in this demo app` = data.frame(
          Packages = c(
            "teal.modules.general",
            "teal.modules.clinical",
            "haven"
          )
        ))
      ),
      tm_variable_browser("Variable Browser")
    )
  }
  # 返回ml列表
  return(ml)
}




########################################################################################

app <- init(
  title = build_app_title("TabulationViewer Demo App", nest_logo),
  header = header,
  footer = footer,
  data = teal_data_module(
    ui = function(id) {
      ns <- NS(id)
      fluidPage(
        mainPanel(
          shiny::fileInput(ns("file"), "Upload a file", multiple = TRUE,
                           accept = c(".csv", ".xlsx", ".xpt", ".sas7bdat")),
          actionButton(ns("submit"), "Submit"),
          DT::dataTableOutput(ns("preview"))
        ),
        fluidRow(
          column(12,
                 tags$footer(
                   'The supported file types for upload include ".csv", ".xlsx", ".xpt", and ".sas7bdat". Please note that do not upload data files with the same name across all types. For example: ["ae.xpt" & "ae.xpt"] or ["dm.xpt" & "dm.sas7bdat"] are invalid.',
                   style = "text-align: left; padding: 13px;")
          )
        )
      )
    },
    server = function(id) {
      moduleServer(id, function(input, output, session) {
        
        data <- eventReactive(input$submit, {
          req(input$file)

          file_paths <- input$file$datapath
          file_names <<- tools::file_path_sans_ext(input$file$name)
          ml_x <<- choose_modules(file_names)
          ##############################################   
          # Target SortInfo file
          target_file <- "SortInfo"
          # Find the index of the target file
          SortInfo_index <- which(file_names == target_file)
          if (length(SortInfo_index) == 0) {
            showNotification("The specified file was not uploaded. Summary table won't be applied.", type = "warning")
            SortInfo_path<-"NOT UPLOADED"
            SortInfo_list<-"NOT UPLOADED"
          }
          else {
            # Get the path of the target file
            SortInfo_path <- file_paths[SortInfo_index]
            
            # Read the target file using function `import_sort_list`
            SortInfo_list <- import_sort_list(SortInfo_path)
          }
          ##############################################   
          #Create teal_data() object
          td <- teal_data()
          for (i in seq_along(file_paths)) {
            if (i == SortInfo_path) {
              next  # Skip the target file
            }
            td <- within(
              td, 
              file_ext=tools::file_ext(file_paths[i]),
              data_name <- switch(
                file_ext,
                "csv" = read_csv(data_path),
                "xlsx" = read_excel(data_path),
                "xpt" = read_xpt(data_path),
                "sas7bdat" = read_sas(data_path),
                stop("Please ensure that the uploaded file type is valid.")
              ),
              data_name = file_names[i], 
              data_path = file_paths[i]
            )
          }
          datanames(td) <-  file_names
          # Generate join_key object using function `generate_join_keys`
          join_keys(td)  <- generate_join_keys(SortInfo_list)
          td
        })
        data
      })
    }
  ),

  # 将模块列表传入 modules 函数
  modules = ml_x
)

shinyApp(app$ui, app$server)


