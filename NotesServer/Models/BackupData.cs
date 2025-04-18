using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace NotesServer.Models;

public class BackupData
{
    public BackupData()
    {
        DatabaseId = string.Empty;
        UserId = string.Empty;
        CreatedAt = DateTime.UtcNow;
        LastModified = DateTime.UtcNow;
    }

    [JsonPropertyName("folders")]
    public List<Folder> Folders { get; set; } = new();

    [JsonPropertyName("notes")]
    public List<Note> Notes { get; set; } = new();

    [JsonPropertyName("scheduleEntries")]
    public List<ScheduleEntry> ScheduleEntries { get; set; } = new();

    [JsonPropertyName("pinboardNotes")]
    public List<PinboardNote> PinboardNotes { get; set; } = new();

    [JsonPropertyName("connections")]
    public List<Connection> Connections { get; set; } = new();

    [JsonPropertyName("noteImages")]
    public List<NoteImage> NoteImages { get; set; } = new();

    [JsonPropertyName("lastModified")]
    public DateTime LastModified { get; set; }

    [JsonPropertyName("createdAt")]
    public DateTime CreatedAt { get; set; }

    [JsonPropertyName("databaseId")]
    public string DatabaseId { get; set; }

    [JsonPropertyName("userId")]
    public string UserId { get; set; }
}

public class FolderData
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("name")]
    public string Name { get; set; } = null!;

    [JsonPropertyName("color")]
    public string Color { get; set; } = "FF424242";

    [JsonPropertyName("isExpanded")]
    public bool IsExpanded { get; set; }
}

public class NoteData
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("title")]
    public string Title { get; set; } = null!;

    [JsonPropertyName("content")]
    public string Content { get; set; } = null!;

    [JsonPropertyName("folderId")]
    public int? FolderId { get; set; }

    [JsonPropertyName("createdAt")]
    public DateTime CreatedAt { get; set; }

    [JsonPropertyName("updatedAt")]
    public DateTime UpdatedAt { get; set; }

    [JsonPropertyName("images")]
    public List<string>? Images { get; set; }

    [JsonPropertyName("metadata")]
    public Dictionary<string, string>? Metadata { get; set; }

    [JsonPropertyName("content_json")]
    public string? ContentJson { get; set; }
}

public class ScheduleEntryData
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("time")]
    public string Time { get; set; } = null!;

    [JsonPropertyName("date")]
    public string Date { get; set; } = null!;

    [JsonPropertyName("note")]
    public string Note { get; set; } = null!;

    [JsonPropertyName("dynamicFieldsJson")]
    public string? DynamicFieldsJson { get; set; }
}

public class PinboardNoteData
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("content")]
    public string Content { get; set; } = string.Empty;

    [JsonPropertyName("positionX")]
    public double PositionX { get; set; }

    [JsonPropertyName("positionY")]
    public double PositionY { get; set; }

    [JsonPropertyName("width")]
    public double Width { get; set; } = 200.0;

    [JsonPropertyName("height")]
    public double Height { get; set; } = 150.0;

    [JsonPropertyName("backgroundColor")]
    public double BackgroundColor { get; set; }

    [JsonPropertyName("icon")]
    public string Icon { get; set; } = string.Empty;
}

public class ConnectionData
{
    [JsonPropertyName("id")]
    public int Id { get; set; }

    [JsonPropertyName("fromId")]
    public int FromId { get; set; }

    [JsonPropertyName("toId")]
    public int ToId { get; set; }

    [JsonPropertyName("name")]
    public string Name { get; set; } = null!;

    [JsonPropertyName("connectionColor")]
    public string ConnectionColor { get; set; } = null!;
}

public class ImageData
{
    [JsonPropertyName("note_id")]
    public int NoteId { get; set; }

    [JsonPropertyName("file_name")]
    public string FileName { get; set; } = null!;

    [JsonPropertyName("image_data")]
    public string Base64Data { get; set; } = null!;
} 