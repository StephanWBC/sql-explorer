using System.Collections.ObjectModel;
using System.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using SqlStudio.Core.Interfaces;
using SqlStudio.Core.Models;

namespace SqlStudio.App.ViewModels;

public partial class QueryTabViewModel : ViewModelBase
{
    private readonly IQueryExecutionService _queryService;
    private CancellationTokenSource? _cts;

    [ObservableProperty] private string _title = "Query";
    [ObservableProperty] private string _sqlText = string.Empty;
    [ObservableProperty] private bool _isExecuting;
    [ObservableProperty] private string _statusMessage = "Ready";
    [ObservableProperty] private DataTable? _resultData;
    [ObservableProperty] private string _messagesText = string.Empty;
    [ObservableProperty] private bool _hasResults;
    [ObservableProperty] private bool _hasError;
    [ObservableProperty] private string _errorMessage = string.Empty;
    [ObservableProperty] private int _selectedResultsTab;

    public Guid ConnectionId { get; set; }
    public string DatabaseName { get; set; } = "master";
    public QueryResult? LastResult { get; private set; }

    public QueryTabViewModel(IQueryExecutionService queryService)
    {
        _queryService = queryService;
    }

    [RelayCommand]
    private async Task ExecuteQueryAsync()
    {
        if (string.IsNullOrWhiteSpace(SqlText) || ConnectionId == Guid.Empty)
            return;

        IsExecuting = true;
        HasResults = false;
        HasError = false;
        ErrorMessage = string.Empty;
        MessagesText = string.Empty;
        ResultData = null;

        _cts = new CancellationTokenSource();

        try
        {
            StatusMessage = "Executing query...";
            var result = await _queryService.ExecuteQueryAsync(ConnectionId, SqlText, DatabaseName, _cts.Token);
            LastResult = result;

            if (result.IsError)
            {
                HasError = true;
                ErrorMessage = result.ErrorMessage!;
                MessagesText = result.ErrorMessage!;
                SelectedResultsTab = 1; // Switch to messages tab
                StatusMessage = "Query completed with errors";
            }
            else
            {
                HasResults = true;
                ResultData = ConvertToDataTable(result);

                var messages = string.Join(Environment.NewLine, result.Stats.Messages);
                MessagesText = string.IsNullOrEmpty(messages)
                    ? $"({result.Stats.RowsAffected} rows affected)"
                    : messages + $"\n({result.Stats.RowsAffected} rows affected)";

                StatusMessage = $"{result.Stats.RowsAffected} rows returned in {result.Stats.ElapsedMilliseconds}ms";

                if (result.HasMoreRows)
                    MessagesText += "\n\nWarning: Results were truncated. Only first 50,000 rows shown.";
            }
        }
        catch (OperationCanceledException)
        {
            StatusMessage = "Query cancelled";
            MessagesText = "Query execution was cancelled by user.";
        }
        catch (Exception ex)
        {
            HasError = true;
            ErrorMessage = ex.Message;
            MessagesText = ex.Message;
            StatusMessage = "Error";
        }
        finally
        {
            IsExecuting = false;
            _cts?.Dispose();
            _cts = null;
        }
    }

    [RelayCommand]
    private void CancelQuery()
    {
        _cts?.Cancel();
    }

    private static DataTable ConvertToDataTable(QueryResult result)
    {
        var dt = new DataTable();
        foreach (var col in result.Columns)
        {
            dt.Columns.Add(col.Name, typeof(string));
        }

        foreach (var row in result.Rows)
        {
            var dr = dt.NewRow();
            for (var i = 0; i < row.Length; i++)
            {
                dr[i] = row[i]?.ToString() ?? "NULL";
            }
            dt.Rows.Add(dr);
        }

        return dt;
    }
}
