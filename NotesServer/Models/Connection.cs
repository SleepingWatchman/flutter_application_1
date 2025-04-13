using SQLite;
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using System;

namespace NotesServer.Models
{
    public class Connection : DatabaseEntity
    {
        [PrimaryKey, AutoIncrement]
        [JsonPropertyName("id")]
        public int Id { get; set; }

        [JsonPropertyName("fromNoteId")]
        public int FromNoteId { get; set; }

        [JsonPropertyName("toNoteId")]
        public int ToNoteId { get; set; }

        [Required]
        [JsonPropertyName("type")]
        public string Type { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("connectionColor")]
        public int ConnectionColor { get; set; }

        [Required]
        public string ConnectionString { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }
} 