using SQLite;
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;
using System;

namespace NotesServer.Models
{
    public class Folder : DatabaseEntity
    {
        [PrimaryKey, AutoIncrement]
        [JsonPropertyName("id")]
        public int Id { get; set; }
        [Required]
        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;
        public int? ParentId { get; set; }
        public DateTime CreatedAt { get; set; }
        [JsonPropertyName("color")]
        public int Color { get; set; }
        [JsonPropertyName("isExpanded")]
        public bool IsExpanded { get; set; } = true;
    }
} 