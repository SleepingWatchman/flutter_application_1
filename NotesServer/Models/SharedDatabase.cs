using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;

namespace NotesServer.Models
{
    [Index(nameof(OwnerId))]
    public class SharedDatabase
    {
        [Key]
        public required string Id { get; set; }
        
        [Required]
        public required string Name { get; set; }
        
        [Required]
        public required string OwnerId { get; set; }
        
        [Required]
        public DateTime CreatedAt { get; set; }
        
        [Required]
        public string CollaboratorsJson { get; set; } = "[]";
        
        [NotMapped]
        [JsonIgnore]
        public List<string> Collaborators 
        { 
            get 
            {
                try
                {
                    if (string.IsNullOrEmpty(CollaboratorsJson) || CollaboratorsJson == "null")
                    {
                        return new List<string>();
                    }
                    return JsonSerializer.Deserialize<List<string>>(CollaboratorsJson) ?? new List<string>();
                }
                catch (JsonException)
                {
                    return new List<string>();
                }
            }
            set => CollaboratorsJson = JsonSerializer.Serialize(value ?? new List<string>());
        }

        [Required]
        public required string DatabasePath { get; set; }
    }
} 